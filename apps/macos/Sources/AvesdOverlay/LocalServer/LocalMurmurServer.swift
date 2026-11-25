import CAvesdCore
import Combine
import Foundation

@MainActor
final class LocalMurmurServer: ObservableObject {
    enum State: Equatable {
        case stopped, starting, running(UInt16), failed(String)
        var isRunning: Bool { if case .running = self { true } else { false } }
    }

    @Published private(set) var state = State.stopped
    private(set) var token: String?
    private let events: LocalEventStore
    private let port: UInt16
    private let credential: (_ reset: Bool) throws -> String
    private let allowsTrigger: () -> Bool
    private let trigger: (String, Data) -> EventPolling.TriggerResult
    private let onReady: () -> Void
    private var listener: LoopbackHTTPListener?

    init(port: UInt16, database: URL, credential: @escaping (Bool) throws -> String,
         allowsTrigger: @escaping () -> Bool, trigger: @escaping (String, Data) -> EventPolling.TriggerResult,
         onReady: @escaping () -> Void) {
        self.port = port
        events = LocalEventStore(url: database)
        self.credential = credential
        self.allowsTrigger = allowsTrigger
        self.trigger = trigger
        self.onReady = onReady
    }

    func start() {
        guard listener == nil else { return }
        state = .starting
        do {
            token = try credential(false)
            let transport = try LoopbackHTTPListener(port: port) { [weak self] request in
                guard let self, state.isRunning else { return .error(503, "server_stopped") }
                return await handle(request)
            }
            listener = transport
            transport.start { [weak self] port in
                self?.state = .running(port)
                self?.onReady()
            } failed: { [weak self] error in
                self?.stop()
                self?.state = .failed(error.localizedDescription)
            }
        } catch {
            token = nil
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
        token = nil
        state = .stopped
    }

    func resetToken() throws { token = try credential(true) }

    private struct Envelope: Decodable {
        let id: String
        let expires_at: String?
    }

    private func handle(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        let path = request.url.percentEncodedPath.components(separatedBy: "/")
        let regional = path.count == 5 && path[0...2] == ["", "v1", "regions"] && path[4] == "event"
        let put = path.count == 4 && path[0...2] == ["", "v1", "events"] && !path[3].isEmpty
        let immediate = path == ["", "v1", "trigger"]
        guard regional || put || immediate else { return .error(404, "unknown_endpoint") }
        let method = regional ? "GET" : (put ? "PUT" : "POST")
        guard request.method == method else { return LocalHTTPResponse(status: 405, headers: ["Allow": method]) }

        if regional {
            guard let cell = UInt64(path[3], radix: 16), String(cell, radix: 16) == path[3],
                  avesd_region_is_valid(cell) else { return .error(400, "invalid_region") }
            var query = request.url
            query.percentEncodedQuery = query.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
            let played = (query.queryItems ?? []).filter { $0.name == "played" }.map { $0.value ?? "" }
            guard played.count <= 64, played.allSatisfy({ $0.utf8.count <= 256 }) else {
                return .error(400, "invalid_playback_history")
            }
            do {
                if let data = try await events.candidate(excluding: played) { return LocalHTTPResponse(status: 200, body: data) }
                return LocalHTTPResponse(status: 204)
            } catch { return .error(503, "storage_unavailable") }
        }

        let auth = request.authorization?.split(separator: " ", maxSplits: 1)
        guard let token, let auth, auth.count == 2, auth[0].lowercased() == "bearer", auth[1] == token else {
            var response = LocalHTTPResponse.error(401, "invalid_token")
            response.headers["WWW-Authenticate"] = "Bearer"
            return response
        }
        if immediate && !allowsTrigger() { return .error(403, "trigger_disabled") }
        guard let event = try? JSONDecoder().decode(Envelope.self, from: request.body),
              !event.id.isEmpty, event.id.utf8.count <= 256,
              request.body.withUnsafeBytes({ avesd_event_is_playable($0.bindMemory(to: UInt8.self).baseAddress, $0.count) }) else {
            return .error(422, "invalid_event")
        }
        var expires: Date?
        if let timestamp = event.expires_at {
            let date = (try? Date(timestamp, strategy: .iso8601)) ??
                (try? Date(timestamp, strategy: .iso8601.time(includingFractionalSeconds: true)))
            guard let date else { return .error(422, "invalid_expiry") }
            guard date > .now else { return .error(422, "event_expired") }
            expires = date
        }
        if immediate {
            let result = trigger(event.id, request.body)
            if result == .unavailable { return .error(503, "playback_unavailable") }
            return .json(200, ["id": event.id, "status": result.rawValue])
        }
        guard path[3].removingPercentEncoding == event.id else { return .error(422, "id_mismatch") }
        do {
            let created = try await events.put(id: event.id, event: request.body, expires: expires)
            return .json(created ? 201 : 200, ["id": event.id])
        } catch { return .error(503, "storage_unavailable") }
    }
}
