import Foundation
import SQLite3

actor LocalEventStore {
    struct Candidate {
        let id: String
        let expires: TimeInterval
        let data: Data
    }

    private let url: URL
    private var database: EventDatabase?

    init(url: URL) { self.url = url }

    private func connection() throws -> EventDatabase {
        if let database { return database }
        let database = try EventDatabase(url: url)
        self.database = database
        return database
    }

    func put(id: String, event: Data, expires: Date?, now: Date = .now) throws -> Bool {
        try connection().put(id: id, event: event, expires: expires, now: now)
    }

    func candidate(excluding played: [String], now: Date = .now) throws -> Data? {
        try connection().candidate(excluding: played, now: now)
    }

    func nextCandidate(excluding played: Set<String>, now: Date) throws -> Candidate? {
        try connection().nextCandidate(excluding: played, now: now)
    }
}

private final class EventDatabase {
    private enum StoreError: Error { case database }
    private let handle: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var opened: OpaquePointer?
        guard sqlite3_open(url.path, &opened) == SQLITE_OK, let opened else {
            sqlite3_close(opened)
            throw StoreError.database
        }
        let schema = "CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, expires REAL NOT NULL, event BLOB NOT NULL)"
        guard sqlite3_exec(opened, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(opened)
            throw StoreError.database
        }
        handle = opened
    }

    deinit { sqlite3_close(handle) }

    private func statement<T>(_ sql: String, _ perform: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.database
        }
        defer { sqlite3_finalize(statement) }
        return try perform(statement)
    }

    private func removeExpired(at now: Date) throws {
        try statement("DELETE FROM events WHERE expires <= ?") { query in
            sqlite3_bind_double(query, 1, now.timeIntervalSince1970)
            guard sqlite3_step(query) == SQLITE_DONE else { throw StoreError.database }
        }
    }

    func put(id: String, event: Data, expires: Date?, now: Date) throws -> Bool {
        try removeExpired(at: now)
        let created = try statement("SELECT 1 FROM events WHERE id = ?") { query in
            sqlite3_bind_text(query, 1, id, Int32(id.utf8.count), transient)
            switch sqlite3_step(query) {
            case SQLITE_ROW: return false
            case SQLITE_DONE: return true
            default: throw StoreError.database
            }
        }
        // A retry with no explicit expiry keeps the candidate's original deadline.
        let sql = """
            INSERT INTO events (id, expires, event) VALUES (?, COALESCE(?, ?), ?)
            ON CONFLICT(id) DO UPDATE SET expires = COALESCE(?2, events.expires), event = excluded.event
            """
        try statement(sql) { query in
            sqlite3_bind_text(query, 1, id, Int32(id.utf8.count), transient)
            if let expires { sqlite3_bind_double(query, 2, expires.timeIntervalSince1970) }
            sqlite3_bind_double(query, 3, now.addingTimeInterval(3 * 60 * 60).timeIntervalSince1970)
            let bound = event.withUnsafeBytes {
                sqlite3_bind_blob(query, 4, $0.baseAddress, Int32($0.count), transient)
            }
            guard bound == SQLITE_OK, sqlite3_step(query) == SQLITE_DONE else { throw StoreError.database }
        }
        return created
    }

    func nextCandidate(excluding played: Set<String>, now: Date) throws -> LocalEventStore.Candidate? {
        try removeExpired(at: now)
        return try statement("SELECT id, expires, event FROM events ORDER BY rowid DESC") { query in
            while true {
                switch sqlite3_step(query) {
                case SQLITE_ROW:
                    guard let idBytes = sqlite3_column_text(query, 0) else { throw StoreError.database }
                    let id = String(decoding: UnsafeBufferPointer(start: idBytes,
                                                                  count: Int(sqlite3_column_bytes(query, 0))), as: UTF8.self)
                    if played.contains(id) { continue }
                    let expires = sqlite3_column_double(query, 1)
                    guard let bytes = sqlite3_column_blob(query, 2) else { throw StoreError.database }
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 2)))
                    return LocalEventStore.Candidate(id: id, expires: expires, data: data)
                case SQLITE_DONE: return nil
                default: throw StoreError.database
                }
            }
        }
    }

    func candidate(excluding played: [String], now: Date) throws -> Data? {
        try removeExpired(at: now)
        let parameters = Array(repeating: "?", count: played.count).joined(separator: ",")
        let filter = played.isEmpty ? "" : " WHERE id NOT IN (\(parameters))"
        return try statement("SELECT event FROM events\(filter) ORDER BY rowid DESC LIMIT 1") { query in
            for (index, id) in played.enumerated() {
                sqlite3_bind_text(query, Int32(index + 1), id, Int32(id.utf8.count), transient)
            }
            switch sqlite3_step(query) {
            case SQLITE_DONE: return nil
            case SQLITE_ROW:
                guard let bytes = sqlite3_column_blob(query, 0) else { throw StoreError.database }
                return Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
            default: throw StoreError.database
            }
        }
    }
}
