import Foundation
import SQLite3

// MARK: - SQLite support

extension MessageStore {
    func withDatabase<T>(
        _ operation: (OpaquePointer) throws -> T
    ) throws -> T {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw MessageStoreError.databaseUnavailable
        }

        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard result == SQLITE_OK else {
            let message = database
                .map { String(cString: sqlite3_errmsg($0)) }
                ?? String(cString: sqlite3_errstr(result))
            if let database {
                sqlite3_close_v2(database)
            }
            database = nil
            throw MessageStoreError.databaseOpenFailed(
                "\(message) (SQLite code \(result), path: \(databaseURL.path))"
            )
        }
        guard let database else {
            throw MessageStoreError.databaseOpenFailed("SQLite returned no database connection.")
        }

        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        return try operation(database)
    }

    func prepare(
        _ sql: String,
        in database: OpaquePointer
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    func chatColumns(in database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(chat)", in: database)
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(text(statement, column: 1))
        }
        return columns
    }

    func messageFilterClause(_ filters: ConversationFilters) -> String {
        var conditions: [String] = []

        if !filters.includeSystemEvents {
            conditions.append("COALESCE(m.item_type, 0) = 0")
            conditions.append("COALESCE(m.associated_message_type, 0) NOT BETWEEN 2000 AND 3999")
        }

        switch filters.content {
        case .all:
            break
        case .text:
            conditions.append("COALESCE(m.text, '') != ''")
            conditions.append(
                "NOT EXISTS (SELECT 1 FROM message_attachment_join maj WHERE maj.message_id = m.ROWID)"
            )
        case .attachments:
            conditions.append(
                "EXISTS (SELECT 1 FROM message_attachment_join maj WHERE maj.message_id = m.ROWID)"
            )
        }

        switch filters.direction {
        case .all:
            break
        case .sent:
            conditions.append("m.is_from_me = 1")
        case .received:
            conditions.append("m.is_from_me = 0")
        }

        if !filters.senderHandles.isEmpty {
            let includesCurrentUser = filters.senderHandles.contains("ME")
            let handles = filters.senderHandles
                .filter { $0 != "ME" }
                .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
                .joined(separator: ",")
            if includesCurrentUser, !handles.isEmpty {
                conditions.append("(m.is_from_me = 1 OR (m.is_from_me = 0 AND h.id IN (\(handles))))")
            } else if includesCurrentUser {
                conditions.append("m.is_from_me = 1")
            } else if !handles.isEmpty {
                conditions.append("m.is_from_me = 0 AND h.id IN (\(handles))")
            }
        }

        guard !conditions.isEmpty else { return "" }
        return "AND " + conditions.joined(separator: "\n                    AND ")
    }

    func bind(_ date: Date?, to statement: OpaquePointer, index: Int32) {
        if let date {
            sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    func appleDate(from value: Int64) -> Date? {
        guard value != 0 else { return nil }
        let seconds = abs(value) > 100_000_000_000
            ? Double(value) / 1_000_000_000
            : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    func checkCompletion(
        of statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        let result = sqlite3_errcode(database)
        guard result == SQLITE_OK || result == SQLITE_DONE else {
            throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}
