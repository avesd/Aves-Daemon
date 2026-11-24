import CFNetwork
import Foundation
import Network

struct LocalHTTPRequest {
    let method: String
    let url: URLComponents
    let authorization: String?
    let body: Data
}

struct LocalHTTPResponse {
    let status: Int
    var body = Data()
    var headers: [String: String] = [:]

    static func json(_ status: Int, _ fields: [String: String]) -> Self {
        Self(status: status, body: (try? JSONEncoder().encode(fields)) ?? Data())
    }

    static func error(_ status: Int, _ code: String) -> Self { .json(status, ["error": code]) }

    var wire: Data {
        var fields = headers
        fields["Content-Type"] = "application/json"
        if status != 204 { fields["Content-Length"] = String(body.count) }
        fields["Connection"] = "close"
        fields["Cache-Control"] = "private, no-store"
        let lines = fields.map { "\($0.key): \($0.value)\r\n" }.joined()
        let reason = HTTPURLResponse.localizedString(forStatusCode: status)
        return Data("HTTP/1.1 \(status) \(reason)\r\n\(lines)\r\n".utf8) + body
    }
}

@MainActor
final class LoopbackHTTPListener {
    typealias Handler = @MainActor (LocalHTTPRequest) async -> LocalHTTPResponse
    private static let headerEnd = Data("\r\n\r\n".utf8)
    private static let maxHeaders = 64 * 1024
    private static let maxBody = 64 * 1024

    private let listener: NWListener
    private let handle: Handler
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var accepting = false

    init(port: UInt16, handle: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
        self.handle = handle
    }

    func start(ready: @escaping @MainActor (UInt16) -> Void, failed: @escaping @MainActor (Error) -> Void) {
        accepting = true
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.accepting else { return }
                switch state {
                case .ready:
                    if let port = self.listener.port { ready(port.rawValue) }
                case .failed(let error), .waiting(let error): failed(error)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self, self.accepting, self.clients.count < 32 else { connection.cancel(); return }
                self.clients[ObjectIdentifier(connection)] = connection
                connection.start(queue: .main)
                self.receive(connection, buffered: Data())
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak connection] in
                    if let connection { self?.close(connection) }
                }
            }
        }
        listener.start(queue: .main)
    }

    func stop() {
        accepting = false
        listener.cancel()
        for client in clients.values { client.cancel() }
        clients.removeAll()
    }

    private func close(_ connection: NWConnection) {
        clients.removeValue(forKey: ObjectIdentifier(connection))?.cancel()
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] bytes, _, end, error in
            Task { @MainActor in
                guard let self, self.clients[ObjectIdentifier(connection)] != nil else { return }
                if error != nil { self.close(connection); return }
                var data = buffered
                if let bytes { data.append(bytes) }
                switch self.parse(data) {
                case .incomplete:
                    if end { self.close(connection) } else { self.receive(connection, buffered: data) }
                case .rejected(let response): self.send(response, on: connection)
                case .complete(let request):
                    let response = await self.handle(request)
                    if self.clients[ObjectIdentifier(connection)] != nil { self.send(response, on: connection) }
                }
            }
        }
    }

    private func send(_ response: LocalHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.wire, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.close(connection) }
        })
    }

    private enum Message {
        case incomplete, rejected(LocalHTTPResponse), complete(LocalHTTPRequest)
    }

    private func parse(_ data: Data) -> Message {
        guard let end = data.range(of: Self.headerEnd)?.upperBound else {
            return data.count > Self.maxHeaders ? .rejected(.error(431, "headers_too_large")) : .incomplete
        }
        guard end <= Self.maxHeaders else { return .rejected(.error(431, "headers_too_large")) }
        let message = CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue()
        let parsed = data.withUnsafeBytes {
            CFHTTPMessageAppendBytes(message, $0.bindMemory(to: UInt8.self).baseAddress!, end)
        }
        guard parsed, CFHTTPMessageIsHeaderComplete(message),
              let method = CFHTTPMessageCopyRequestMethod(message)?.takeRetainedValue() as String?,
              let rawURL = CFHTTPMessageCopyRequestURL(message)?.takeRetainedValue() as URL?,
              let url = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else {
            return .rejected(.error(400, "invalid_request"))
        }
        func header(_ name: String) -> String? {
            CFHTTPMessageCopyHeaderFieldValue(message, name as CFString)?.takeRetainedValue() as String?
        }
        guard let port = listener.port?.rawValue, let host = header("Host")?.lowercased(),
              host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            return .rejected(.error(400, "invalid_host"))
        }
        guard header("Transfer-Encoding") == nil else { return .rejected(.error(501, "unsupported_transfer_encoding")) }
        let length = header("Content-Length") ?? "0"
        guard !length.isEmpty, length.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(length) else {
            return .rejected(.error(400, "invalid_content_length"))
        }
        guard count <= Self.maxBody else { return .rejected(.error(413, "event_too_large")) }
        guard data.count >= end + count else { return .incomplete }
        guard data.count == end + count else { return .rejected(.error(400, "invalid_content_length")) }
        return .complete(LocalHTTPRequest(method: method, url: url, authorization: header("Authorization"),
                                          body: data.subdata(in: end..<data.count)))
    }
}
