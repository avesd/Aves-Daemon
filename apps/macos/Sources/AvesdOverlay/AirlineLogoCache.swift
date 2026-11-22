import AppKit

/// The CDN supplies monochrome marks, addressed by the carrier's catalog slug.
struct AirlineMark: Hashable, Sendable {
    let slug: String

    init?(slug: String) {
        guard !slug.isEmpty, slug.utf8.count <= 100, slug.utf8.allSatisfy({
            (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }) else { return nil }
        self.slug = slug
    }

    static let united = AirlineMark(slug: "united-airlines")!
    static let common = [united, AirlineMark(slug: "delta-air-lines")!, AirlineMark(slug: "lufthansa")!]
}

struct LogoCacheStatistics: Sendable {
    let count: Int
    let bytes: Int
    let isEmpty: Bool
}

actor AirlineLogoCache {
    static let didChange = Notification.Name("AvesDaemonLogoCacheChanged")
    private let directory: URL
    private let session: URLSession
    private let fileManager = FileManager.default
    private var downloads: [AirlineMark: Task<Data?, Never>] = [:]
    private var retryAfter: [AirlineMark: Date] = [:]
    private let lifetime: TimeInterval = 30 * 24 * 3600
    private let byteLimit = 4 * 1024 * 1024

    init(directory: URL, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.directory = directory
        self.session = session
    }

    func logo(for mark: AirlineMark) async -> Data? {
        guard !Task.isCancelled else { return nil }
        let file = directory.appendingPathComponent(mark.slug + ".svg")
        let cached = try? Data(contentsOf: file)
        let usable = cached.flatMap { NSImage(data: $0) == nil ? nil : $0 }
        let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let usable, let modified, Date().timeIntervalSince(modified) < lifetime { return usable }
        if let retry = retryAfter[mark], retry > Date() { return usable }

        let task: Task<Data?, Never>
        if let pending = downloads[mark] {
            task = pending
        } else {
            task = Task { await refresh(mark, at: file) }
            downloads[mark] = task
            notifyChange()
        }
        if let usable { return usable }
        return await task.value
    }

    private func refresh(_ mark: AirlineMark, at file: URL) async -> Data? {
        defer {
            // A clear can cancel this task and start a new lookup for the same mark.
            if !Task.isCancelled {
                downloads[mark] = nil
                notifyChange()
            }
        }
        guard !Task.isCancelled else { return nil }
        let url = URL(string: "https://cdn.jsdelivr.net/npm/soaring-symbols@0.4/dist/assets/\(mark.slug)/icon-mono.svg")!
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.mimeType == "image/svg+xml", data.count <= 256 * 1024,
                  NSImage(data: data) != nil else { throw URLError(.cannotDecodeContentData) }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            trim()
            retryAfter[mark] = nil
            return data
        } catch {
            if !Task.isCancelled { retryAfter[mark] = Date().addingTimeInterval(5 * 60) }
            return nil
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private func files() throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                       options: .skipsHiddenFiles).filter { $0.pathExtension == "svg" }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    func statistics() throws -> LogoCacheStatistics {
        let urls = try files()
        let bytes = try urls.reduce(0) { total, file in
            total + (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        return LogoCacheStatistics(count: urls.count, bytes: bytes, isEmpty: urls.isEmpty && downloads.isEmpty)
    }

    func clear() throws {
        for task in downloads.values { task.cancel() }
        downloads.removeAll()
        retryAfter.removeAll()
        defer { notifyChange() }
        for file in try files() { try fileManager.removeItem(at: file) }
    }

    private func trim() {
        guard let files = try? files() else { return }
        let entries = files.compactMap { url -> (URL, Date, Int)? in
            guard let info = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]), let size = info.fileSize else { return nil }
            return (url, info.contentModificationDate ?? .distantPast, size)
        }.sorted { $0.1 < $1.1 }
        var total = entries.reduce(0) { $0 + $1.2 }
        for (file, _, size) in entries where total > byteLimit {
            if (try? fileManager.removeItem(at: file)) != nil { total -= size }
        }
    }
}
