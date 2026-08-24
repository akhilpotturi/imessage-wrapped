import Foundation
import SQLite3

// MARK: - Message highlights

extension MessageStore {
    func loadMessageHighlights(
        chatIDs: [Int64],
        since startDate: Date?
    ) throws -> [RawMessageHighlight] {
        guard !chatIDs.isEmpty else { return [] }

        return try withDatabase { database in
            let attachmentsByMessage = try loadMessageAttachments(
                database: database,
                chatIDs: chatIDs
            )
            let placeholders = chatIDs.indices.map { "?\($0 + 1)" }.joined(separator: ",")
            let sql = """
                SELECT
                    m.ROWID,
                    COALESCE(m.guid, ''),
                    m.date,
                    m.is_from_me,
                    CASE
                        WHEN m.is_from_me = 1 THEN 'ME'
                        ELSE COALESCE(h.id, 'Unknown')
                    END,
                    COALESCE(m.text, ''),
                    m.attributedBody,
                    COALESCE(m.item_type, 0),
                    COALESCE(m.associated_message_type, 0),
                    COALESCE(m.associated_message_guid, '')
                FROM chat_message_join cmj
                JOIN message m ON m.ROWID = cmj.message_id
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                WHERE cmj.chat_id IN (\(placeholders))
                GROUP BY m.ROWID
                ORDER BY m.date
                """
            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            for (index, chatID) in chatIDs.enumerated() {
                sqlite3_bind_int64(statement, Int32(index + 1), chatID)
            }

            var messages: [(
                id: Int64,
                guid: String,
                date: Date,
                isCurrentUser: Bool,
                sender: String,
                text: String,
                attachments: [MessageAttachment]
            )] = []
            var reactionNet: [ActiveReactionKey: Int] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let date = appleDate(from: sqlite3_column_int64(statement, 2)) else {
                    continue
                }
                let associatedType = Int(sqlite3_column_int(statement, 8))
                let isReaction = (2000...2005).contains(associatedType)
                    || (3000...3005).contains(associatedType)
                let isCurrentUser = sqlite3_column_int(statement, 3) == 1
                let sender = isCurrentUser ? "ME" : text(statement, column: 4)

                if isReaction {
                    let associatedGUID = text(statement, column: 9)
                    let targetGUID = associatedGUID.split(separator: "/").last.map(String.init)
                        ?? associatedGUID
                    let typeValue = associatedType >= 3000
                        ? associatedType - 3000
                        : associatedType - 2000
                    guard let type = ReactionType(rawValue: typeValue), !targetGUID.isEmpty else {
                        continue
                    }
                    let key = ActiveReactionKey(
                        targetGUID: targetGUID,
                        type: type,
                        giver: sender
                    )
                    reactionNet[key, default: 0] += associatedType >= 3000 ? -1 : 1
                    continue
                }

                let itemType = Int(sqlite3_column_int(statement, 7))
                let messageText = decodedMessageText(
                    statement,
                    textColumn: 5,
                    attributedBodyColumn: 6
                )
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isInRange = startDate.map { date >= $0 } ?? true
                let messageID = sqlite3_column_int64(statement, 0)
                let attachments = attachmentsByMessage[messageID, default: []]
                guard itemType == 0,
                      associatedType == 0,
                      !messageText.isEmpty || !attachments.isEmpty,
                      isInRange else {
                    continue
                }
                messages.append(
                    (
                        id: messageID,
                        guid: text(statement, column: 1),
                        date: date,
                        isCurrentUser: isCurrentUser,
                        sender: sender,
                        text: messageText,
                        attachments: attachments
                    )
                )
            }
            try checkCompletion(of: statement, in: database)

            var reactionsByMessage: [String: [ReactionType: Int]] = [:]
            for (key, count) in reactionNet where count > 0 {
                reactionsByMessage[key.targetGUID, default: [:]][key.type, default: 0] += 1
            }

            return messages.map {
                RawMessageHighlight(
                    id: $0.id,
                    senderHandle: $0.sender,
                    isCurrentUser: $0.isCurrentUser,
                    text: $0.text,
                    date: $0.date,
                    reactionsByType: reactionsByMessage[$0.guid, default: [:]],
                    attachments: $0.attachments
                )
            }
        }
    }

    func loadMessageContext(
        chatIDs: [Int64],
        around messageID: Int64,
        radius: Int
    ) throws -> [RawMessageContextEntry] {
        guard !chatIDs.isEmpty, radius >= 0 else { return [] }

        return try withDatabase { database in
            let placeholders = chatIDs.indices.map { "?\($0 + 1)" }.joined(separator: ",")
            let messageParameter = chatIDs.count + 1
            let radiusParameter = chatIDs.count + 2
            let sql = """
                WITH distinct_messages AS (
                    SELECT
                        m.ROWID AS message_id,
                        m.date,
                        m.is_from_me,
                        CASE
                            WHEN m.is_from_me = 1 THEN 'ME'
                            ELSE COALESCE(h.id, 'Unknown')
                        END AS sender,
                        COALESCE(m.text, '') AS message_text,
                        m.attributedBody AS attributed_body
                    FROM chat_message_join cmj
                    JOIN message m ON m.ROWID = cmj.message_id
                    LEFT JOIN handle h ON h.ROWID = m.handle_id
                    WHERE cmj.chat_id IN (\(placeholders))
                        AND COALESCE(m.item_type, 0) = 0
                        AND COALESCE(m.associated_message_type, 0) = 0
                        AND (
                            COALESCE(m.text, '') != ''
                            OR m.attributedBody IS NOT NULL
                            OR EXISTS (
                                SELECT 1
                                FROM message_attachment_join maj
                                WHERE maj.message_id = m.ROWID
                            )
                        )
                    GROUP BY m.ROWID
                ),
                ordered_messages AS (
                    SELECT
                        *,
                        ROW_NUMBER() OVER (ORDER BY date, message_id) AS message_position
                    FROM distinct_messages
                ),
                target AS (
                    SELECT message_position
                    FROM ordered_messages
                    WHERE message_id = ?\(messageParameter)
                )
                SELECT
                    message_id,
                    date,
                    is_from_me,
                    sender,
                    message_text,
                    attributed_body
                FROM ordered_messages, target
                WHERE ordered_messages.message_position
                    BETWEEN target.message_position - ?\(radiusParameter)
                    AND target.message_position + ?\(radiusParameter)
                ORDER BY ordered_messages.message_position
                """
            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            for (index, chatID) in chatIDs.enumerated() {
                sqlite3_bind_int64(statement, Int32(index + 1), chatID)
            }
            sqlite3_bind_int64(statement, Int32(messageParameter), messageID)
            sqlite3_bind_int(statement, Int32(radiusParameter), Int32(radius))

            var entries: [RawMessageContextEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let date = appleDate(from: sqlite3_column_int64(statement, 1)) else {
                    continue
                }
                let messageText = decodedMessageText(
                    statement,
                    textColumn: 4,
                    attributedBodyColumn: 5
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                let messageID = sqlite3_column_int64(statement, 0)
                let isCurrentUser = sqlite3_column_int(statement, 2) == 1
                entries.append(
                    RawMessageContextEntry(
                        id: messageID,
                        senderHandle: isCurrentUser ? "ME" : text(statement, column: 3),
                        isCurrentUser: isCurrentUser,
                        text: messageText,
                        date: date,
                        attachments: []
                    )
                )
            }
            try checkCompletion(of: statement, in: database)
            let attachmentsByMessage = try loadMessageAttachments(
                database: database,
                messageIDs: entries.map(\.id)
            )
            return entries.compactMap { entry in
                let attachments = attachmentsByMessage[entry.id, default: []]
                guard !entry.text.isEmpty || !attachments.isEmpty else { return nil }
                return RawMessageContextEntry(
                    id: entry.id,
                    senderHandle: entry.senderHandle,
                    isCurrentUser: entry.isCurrentUser,
                    text: entry.text,
                    date: entry.date,
                    attachments: attachments
                )
            }
        }
    }

    private func loadMessageAttachments(
        database: OpaquePointer,
        chatIDs: [Int64]
    ) throws -> [Int64: [MessageAttachment]] {
        let placeholders = chatIDs.indices.map { "?\($0 + 1)" }.joined(separator: ",")
        let sql = """
            SELECT DISTINCT
                maj.message_id,
                a.ROWID,
                COALESCE(a.filename, ''),
                COALESCE(NULLIF(a.transfer_name, ''), NULLIF(a.filename, ''), 'Attachment'),
                COALESCE(a.mime_type, ''),
                COALESCE(a.guid, ''),
                m.date
            FROM chat_message_join cmj
            JOIN message_attachment_join maj ON maj.message_id = cmj.message_id
            JOIN attachment a ON a.ROWID = maj.attachment_id
            JOIN message m ON m.ROWID = maj.message_id
            WHERE cmj.chat_id IN (\(placeholders))
            """
        let statement = try prepare(sql, in: database)
        defer { sqlite3_finalize(statement) }
        for (index, chatID) in chatIDs.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), chatID)
        }

        var attachments: [Int64: [MessageAttachment]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            appendAttachment(from: statement, to: &attachments)
        }
        try checkCompletion(of: statement, in: database)
        return attachments
    }

    private func loadMessageAttachments(
        database: OpaquePointer,
        messageIDs: [Int64]
    ) throws -> [Int64: [MessageAttachment]] {
        guard !messageIDs.isEmpty else { return [:] }
        let placeholders = messageIDs.indices.map { "?\($0 + 1)" }.joined(separator: ",")
        let sql = """
            SELECT
                maj.message_id,
                a.ROWID,
                COALESCE(a.filename, ''),
                COALESCE(NULLIF(a.transfer_name, ''), NULLIF(a.filename, ''), 'Attachment'),
                COALESCE(a.mime_type, ''),
                COALESCE(a.guid, ''),
                m.date
            FROM message_attachment_join maj
            JOIN attachment a ON a.ROWID = maj.attachment_id
            JOIN message m ON m.ROWID = maj.message_id
            WHERE maj.message_id IN (\(placeholders))
            """
        let statement = try prepare(sql, in: database)
        defer { sqlite3_finalize(statement) }
        for (index, messageID) in messageIDs.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), messageID)
        }

        var attachments: [Int64: [MessageAttachment]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            appendAttachment(from: statement, to: &attachments)
        }
        try checkCompletion(of: statement, in: database)
        return attachments
    }

    private func appendAttachment(
        from statement: OpaquePointer,
        to attachments: inout [Int64: [MessageAttachment]]
    ) {
        let messageID = sqlite3_column_int64(statement, 0)
        let rawPath = text(statement, column: 2)
        let displayPath = text(statement, column: 3)
        let displayName = URL(fileURLWithPath: displayPath).lastPathComponent

        attachments[messageID, default: []].append(
            MessageAttachment(
                id: sqlite3_column_int64(statement, 1),
                guid: text(statement, column: 5),
                fileURL: attachmentFileURL(from: rawPath),
                displayName: displayName.isEmpty ? "Attachment" : displayName,
                mimeType: text(statement, column: 4),
                messageDate: appleDate(from: sqlite3_column_int64(statement, 6)) ?? .distantPast
            )
        )
    }

    private func attachmentFileURL(from rawPath: String) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        if rawPath.hasPrefix("file://") {
            return URL(string: rawPath)
        }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        let expandedPath = (decodedPath as NSString)
            .expandingTildeInPath
            .replacingOccurrences(of: "$HOME", with: homePath)
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        }
        let homeRelative = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: expandedPath)
        let messagesRelative = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages")
            .appending(path: expandedPath)
        return [homeRelative, messagesRelative].first {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? homeRelative
    }

    private func decodedMessageText(
        _ statement: OpaquePointer,
        textColumn: Int32,
        attributedBodyColumn: Int32
    ) -> String {
        let plainText = text(statement, column: textColumn)
        if !plainText.isEmpty {
            return plainText
        }
        guard let bytes = sqlite3_column_blob(statement, attributedBodyColumn) else {
            return ""
        }
        let length = Int(sqlite3_column_bytes(statement, attributedBodyColumn))
        guard length > 0 else { return "" }

        let data = Data(bytes: bytes, count: length)
        return typedStreamString(from: data)
    }

    private func typedStreamString(from data: Data) -> String {
        let bytes = Array(data)
        let marker = Array("NSString".utf8)
        let preamble: [UInt8] = [0x01, 0x94, 0x84, 0x01, 0x2B]
        var searchStart = 0

        while searchStart + marker.count < bytes.count {
            guard let markerStart = find(marker, in: bytes, from: searchStart) else {
                return ""
            }
            var cursor = markerStart + marker.count
            if bytes.indices.contains(cursor + preamble.count - 1),
               Array(bytes[cursor..<(cursor + preamble.count)]) == preamble {
                cursor += preamble.count
            }
            guard let (stringLength, contentStart) = typedStreamLength(
                in: bytes,
                at: cursor
            ), stringLength > 0, contentStart + stringLength <= bytes.count else {
                searchStart = markerStart + marker.count
                continue
            }
            let content = Data(bytes[contentStart..<(contentStart + stringLength)])
            if let string = String(data: content, encoding: .utf8), !string.isEmpty {
                return string
            }
            searchStart = markerStart + marker.count
        }
        return ""
    }

    private func find(
        _ pattern: [UInt8],
        in bytes: [UInt8],
        from start: Int
    ) -> Int? {
        guard !pattern.isEmpty, start < bytes.count, pattern.count <= bytes.count else {
            return nil
        }
        let lastStart = bytes.count - pattern.count
        guard start <= lastStart else { return nil }
        for index in start...lastStart
        where bytes[index..<(index + pattern.count)].elementsEqual(pattern) {
            return index
        }
        return nil
    }

    private func typedStreamLength(
        in bytes: [UInt8],
        at index: Int
    ) -> (length: Int, contentStart: Int)? {
        guard bytes.indices.contains(index) else { return nil }
        switch bytes[index] {
        case 0x81:
            guard bytes.indices.contains(index + 2) else { return nil }
            let length = Int(bytes[index + 1]) | (Int(bytes[index + 2]) << 8)
            return (length, index + 3)
        case 0x82:
            guard bytes.indices.contains(index + 4) else { return nil }
            let length = (0..<4).reduce(0) {
                $0 | (Int(bytes[index + 1 + $1]) << ($1 * 8))
            }
            return (length, index + 5)
        default:
            return (Int(bytes[index]), index + 1)
        }
    }
}
