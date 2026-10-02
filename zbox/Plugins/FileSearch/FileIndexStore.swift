import Foundation
import SQLite3

nonisolated struct IndexedFile: Identifiable, Sendable, Equatable {
    let rootID: UUID
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    var id: String { rootID.uuidString + "/" + path }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }
}

actor FileIndexStore {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "zbox/file-search.sqlite")) { self.url = url }

    private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw FileSearchError.storage
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS files (
                root TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL,
                directory INTEGER NOT NULL, size INTEGER NOT NULL, modified REAL NOT NULL,
                generation TEXT NOT NULL, PRIMARY KEY(root, path));
            CREATE TABLE IF NOT EXISTS cursors (root TEXT PRIMARY KEY, event INTEGER NOT NULL);
            """, nil, nil, nil) == SQLITE_OK else { throw FileSearchError.storage }
        return try body(db)
    }

    private func statement<T>(_ sql: String, db: OpaquePointer, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw FileSearchError.storage }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    func upsert(_ files: [IndexedFile], generation: UUID) throws {
        try database { db in
            guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw FileSearchError.storage }
            do {
                try statement("INSERT OR REPLACE INTO files VALUES (?, ?, ?, ?, ?, ?, ?)", db: db) { stmt in
                    for file in files {
                        try Task.checkCancellation()
                        sqlite3_reset(stmt)
                        bind(file.rootID.uuidString, to: stmt, at: 1)
                        bind(file.path, to: stmt, at: 2)
                        bind(file.name, to: stmt, at: 3)
                        sqlite3_bind_int(stmt, 4, file.isDirectory ? 1 : 0)
                        sqlite3_bind_int64(stmt, 5, file.size)
                        sqlite3_bind_double(stmt, 6, file.modified.timeIntervalSince1970)
                        bind(generation.uuidString, to: stmt, at: 7)
                        guard sqlite3_step(stmt) == SQLITE_DONE else { throw FileSearchError.storage }
                    }
                }
                try Task.checkCancellation()
                guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw FileSearchError.storage }
            } catch { sqlite3_exec(db, "ROLLBACK", nil, nil, nil); throw error }
        }
    }

    // Only called after a complete traversal; failed or cancelled scans never prune old records.
    func finishScan(root: UUID, directory: String, generation: UUID) throws {
        try database { db in
            try statement("DELETE FROM files WHERE root = ? AND generation != ? AND (? = '' OR path = ? OR substr(path, 1, length(?)) = ?)", db: db) { stmt in
                bind(root.uuidString, to: stmt, at: 1)
                bind(generation.uuidString, to: stmt, at: 2)
                bind(directory, to: stmt, at: 3)
                bind(directory, to: stmt, at: 4)
                bind(directory + "/", to: stmt, at: 5)
                bind(directory + "/", to: stmt, at: 6)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw FileSearchError.storage }
            }
        }
    }

    func remove(root: UUID) throws {
        try database { db in
            for table in ["files", "cursors"] {
                try statement("DELETE FROM \(table) WHERE root = ?", db: db) { stmt in
                    bind(root.uuidString, to: stmt, at: 1)
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw FileSearchError.storage }
                }
            }
        }
    }

    func files(root: UUID) throws -> [IndexedFile] {
        try database { db in
            try statement("SELECT path, name, directory, size, modified FROM files WHERE root = ?", db: db) { stmt in
                bind(root.uuidString, to: stmt, at: 1)
                var files: [IndexedFile] = []
                var result = sqlite3_step(stmt)
                while result == SQLITE_ROW {
                    try Task.checkCancellation()
                    files.append(IndexedFile(rootID: root, path: text(stmt, 0), name: text(stmt, 1),
                        isDirectory: sqlite3_column_int(stmt, 2) != 0, size: sqlite3_column_int64(stmt, 3),
                        modified: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))))
                    result = sqlite3_step(stmt)
                }
                guard result == SQLITE_DONE else { throw FileSearchError.storage }
                return files
            }
        }
    }
}
