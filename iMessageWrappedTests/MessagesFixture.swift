import Foundation
import SQLite3

/// Builds a throwaway `chat.db` that mirrors the parts of Apple's Messages
/// schema the app queries. Every test gets its own copy in a temp directory.
///
/// Fixture contents (all dates in local time):
///
/// Chat 1 — direct with Alex (+15550001111)
///   m1  day 1 10:00  ME    "hey"
///   m2  day 1 10:01  Alex  "hi!"
///   m3  day 1 10:02  Alex  ❤️ loved m1
///   m4  day 2 09:00  ME    (attachment, no text)
///   m5  day 2 09:30  Alex  system event (item_type 1)
///
/// Chat 2 — group "Weekend Crew" with Sam and Jordan
///   g1  day 3 18:00  Sam     "plans?"
///   g2  day 3 18:01  Jordan  "in"
///   g3  day 3 18:02  ME      "same"
///   g4  day 3 18:03  Jordan  😂 laughed g1
///   g5  day 3 18:04  Jordan  removed 😂 on g1
///   g6  day 3 18:03  ME      👍 liked g2
///
/// Chat 3 — direct with Jordan, no messages
nonisolated struct MessagesFixture {
    enum Handle {
        static let alex = "+15550001111"
        static let sam = "sam@example.com"
        static let jordan = "+15550002222"
    }

    enum Chat {
        static let alex: Int64 = 1
        static let weekendCrew: Int64 = 2
        static let emptyJordan: Int64 = 3
    }

    let url: URL
    let directory: URL

    static let day1 = localDate(2025, 1, 10)
    static let day2 = localDate(2025, 1, 11)
    static let day3 = localDate(2025, 1, 12)

    /// - Parameter includeLineageColumns: older macOS versions lack
    ///   `chat.group_id` / `chat.original_group_id`; pass `false` to simulate that.
    init(includeLineageColumns: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "iMessageWrappedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "chat.db")

        var database: OpaquePointer?
        guard sqlite3_open(url.path(percentEncoded: false), &database) == SQLITE_OK,
              let database else {
            throw FixtureError("Could not create fixture database")
        }
        defer { sqlite3_close(database) }

        let lineageColumns = includeLineageColumns
            ? ", group_id TEXT, original_group_id TEXT"
            : ""
        try Self.execute(
            """
            CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT NOT NULL);
            CREATE TABLE chat (
                ROWID INTEGER PRIMARY KEY,
                guid TEXT,
                chat_identifier TEXT,
                display_name TEXT\(lineageColumns)
            );
            CREATE TABLE message (
                ROWID INTEGER PRIMARY KEY,
                guid TEXT,
                text TEXT,
                attributedBody BLOB,
                handle_id INTEGER DEFAULT 0,
                date INTEGER,
                is_from_me INTEGER DEFAULT 0,
                item_type INTEGER DEFAULT 0,
                associated_message_type INTEGER DEFAULT 0,
                associated_message_guid TEXT
            );
            CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
            CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
            CREATE TABLE attachment (
                ROWID INTEGER PRIMARY KEY,
                guid TEXT,
                filename TEXT,
                mime_type TEXT,
                transfer_name TEXT,
                total_bytes INTEGER
            );
            CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);

            INSERT INTO handle VALUES
                (1, '\(Handle.alex)'),
                (2, '\(Handle.sam)'),
                (3, '\(Handle.jordan)');
            """,
            in: database
        )

        if includeLineageColumns {
            try Self.execute(
                """
                INSERT INTO chat VALUES
                    (1, 'iMessage;-;\(Handle.alex)', '\(Handle.alex)', '', '', ''),
                    (2, 'iMessage;+;chat123', 'chat123', 'Weekend Crew', 'GROUP-1', ''),
                    (3, 'iMessage;-;\(Handle.jordan)', '\(Handle.jordan)', '', '', '');
                """,
                in: database
            )
        } else {
            try Self.execute(
                """
                INSERT INTO chat VALUES
                    (1, 'iMessage;-;\(Handle.alex)', '\(Handle.alex)', ''),
                    (2, 'iMessage;+;chat123', 'chat123', 'Weekend Crew'),
                    (3, 'iMessage;-;\(Handle.jordan)', '\(Handle.jordan)', '');
                """,
                in: database
            )
        }

        try Self.execute(
            """
            INSERT INTO chat_handle_join VALUES (1, 1), (2, 2), (2, 3), (3, 3);
            """,
            in: database
        )

        let messages: [Message] = [
            Message(id: 1, chat: Chat.alex, guid: "M1", text: "hey", handle: 1, fromMe: true,
                    date: Self.day1.at(10, 0)),
            Message(id: 2, chat: Chat.alex, guid: "M2", text: "hi!", handle: 1,
                    date: Self.day1.at(10, 1)),
            Message(id: 3, chat: Chat.alex, guid: "M3", handle: 1, date: Self.day1.at(10, 2),
                    associatedType: 2000, associatedGUID: "p:0/M1"),
            Message(id: 4, chat: Chat.alex, guid: "M4", handle: 1, fromMe: true,
                    date: Self.day2.at(9, 0), hasAttachment: true),
            Message(id: 5, chat: Chat.alex, guid: "M5", handle: 1, date: Self.day2.at(9, 30),
                    itemType: 1),

            Message(id: 6, chat: Chat.weekendCrew, guid: "G1", text: "plans?", handle: 2,
                    date: Self.day3.at(18, 0)),
            Message(id: 7, chat: Chat.weekendCrew, guid: "G2", text: "in", handle: 3,
                    date: Self.day3.at(18, 1)),
            Message(id: 8, chat: Chat.weekendCrew, guid: "G3", text: "same", handle: 0, fromMe: true,
                    date: Self.day3.at(18, 2)),
            Message(id: 9, chat: Chat.weekendCrew, guid: "G4", handle: 3, date: Self.day3.at(18, 3),
                    associatedType: 2003, associatedGUID: "p:0/G1"),
            Message(id: 10, chat: Chat.weekendCrew, guid: "G5", handle: 3, date: Self.day3.at(18, 4),
                    associatedType: 3003, associatedGUID: "p:0/G1"),
            Message(id: 11, chat: Chat.weekendCrew, guid: "G6", handle: 0, fromMe: true,
                    date: Self.day3.at(18, 3), associatedType: 2001, associatedGUID: "p:0/G2"),
        ]
        for message in messages {
            try insert(message, into: database)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    /// Apple stores message dates as nanoseconds since 2001-01-01.
    static func appleNanoseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate * 1_000_000_000)
    }

    static func localDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct Message {
        let id: Int64
        let chat: Int64
        let guid: String
        var text: String = ""
        let handle: Int64
        var fromMe = false
        let date: Date
        var itemType = 0
        var associatedType = 0
        var associatedGUID = ""
        var hasAttachment = false
    }

    private func insert(_ message: Message, into database: OpaquePointer) throws {
        try Self.execute(
            """
            INSERT INTO message
                (ROWID, guid, text, handle_id, date, is_from_me, item_type,
                 associated_message_type, associated_message_guid)
            VALUES (
                \(message.id), '\(message.guid)', \(message.text.isEmpty ? "NULL" : "'\(message.text)'"),
                \(message.handle), \(Self.appleNanoseconds(message.date)), \(message.fromMe ? 1 : 0),
                \(message.itemType), \(message.associatedType),
                \(message.associatedGUID.isEmpty ? "NULL" : "'\(message.associatedGUID)'")
            );
            INSERT INTO chat_message_join VALUES (\(message.chat), \(message.id));
            """,
            in: database
        )
        if message.hasAttachment {
            try Self.execute(
                """
                INSERT INTO attachment VALUES
                    (\(message.id), 'at_0_\(message.guid)', '~/Library/Messages/Attachments/x.jpg',
                     'image/jpeg', 'x.jpg', 1024);
                INSERT INTO message_attachment_join VALUES (\(message.id), \(message.id));
                """,
                in: database
            )
        }
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw FixtureError(message)
        }
    }
}

nonisolated struct FixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

nonisolated extension Date {
    func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: self)!
    }
}
