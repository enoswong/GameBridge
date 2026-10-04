// SPDX-License-Identifier: GPL-3.0-or-later
import SQLite3
import Darwin
import Foundation

/// Kernel-enforced across processes; acquiring a second writer never waits indefinitely.
public final class ExclusiveFileLock {
    private let descriptor: Int32
    public init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw RuntimeError.io("cannot open lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw RuntimeError.environmentBusy
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

/// Used only inside EngineStore's actor, while holding the cross-process store lock.
final class RuntimeRegistry {
    private var database: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw RuntimeError.database("open")
        }
        do {
            // Install the busy handler before WAL setup, which can itself contend
            // with another app/helper opening or writing this registry.
            sqlite3_busy_timeout(database, 5000)
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;")
            try execute("CREATE TABLE IF NOT EXISTS records (key TEXT PRIMARY KEY, value BLOB NOT NULL);")
        } catch {
            sqlite3_close(database); database = nil
            throw error
        }
    }
    deinit { sqlite3_close(database) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw RuntimeError.database("statement") }
    }
    func put<T: Encodable>(_ value: T, key: String) throws {
        let bytes = try JSONEncoder().encode(value)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO records(key,value) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK else { throw RuntimeError.database("prepare") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK else { throw RuntimeError.database("bind key") }
        let result = bytes.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw RuntimeError.database("write") }
    }
    func get<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM records WHERE key=?", -1, &statement, nil) == SQLITE_OK else { throw RuntimeError.database("prepare") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK else { throw RuntimeError.database("bind") }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else { throw RuntimeError.database("read") }
        return try JSONDecoder().decode(type, from: Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0))))
    }
    func keys(prefix: String) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT key FROM records ORDER BY key", -1, &statement, nil) == SQLITE_OK else { throw RuntimeError.database("prepare") }
        defer { sqlite3_finalize(statement) }
        var keys: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return keys }
            guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw RuntimeError.database("read keys") }
            let key = String(cString: text)
            if key.hasPrefix(prefix) { keys.append(key) }
        }
    }
}
