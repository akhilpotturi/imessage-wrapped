import Foundation
import SQLite3

// MARK: - Participant queries

extension MessageStore {
    func loadParticipantStats(
        chatIDs: [Int64],
        since startDate: Date?,
        filters: ConversationFilters? = nil
    ) throws -> [RawParticipantStats] {
        guard !chatIDs.isEmpty else { return [] }

        return try withDatabase { database in
            let effectiveStartDate = filters?.range.startDate ?? startDate
            let filterClause = filters.map(messageFilterClause) ?? ""
            let placeholders = chatIDs.indices
                .map { "?\($0 + 1)" }
                .joined(separator: ",")
            let dateParameter = chatIDs.count + 1

            let messagesSQL = """
                SELECT
                    m.ROWID,
                    COALESCE(m.guid, ''),
                    m.is_from_me,
                    CASE
                        WHEN m.is_from_me = 1 THEN 'ME'
                        ELSE COALESCE(h.id, 'Unknown')
                    END
                FROM chat_message_join cmj
                JOIN message m ON m.ROWID = cmj.message_id
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                WHERE cmj.chat_id IN (\(placeholders))
                    AND (?\(dateParameter) IS NULL OR (
                        CASE
                            WHEN ABS(m.date) > 100000000000
                                THEN (m.date / 1000000000.0) + 978307200
                            ELSE m.date + 978307200
                        END
                    ) >= ?\(dateParameter))
                    \(filterClause)
                GROUP BY m.ROWID
                """

            var messageCounts: [String: Int] = [:]
            var participantIdentity: [String: (handle: String, isCurrentUser: Bool)] = [:]
            var participantByGUID: [String: String] = [:]

            do {
                let statement = try prepare(messagesSQL, in: database)
                defer { sqlite3_finalize(statement) }
                for (index, chatID) in chatIDs.enumerated() {
                    sqlite3_bind_int64(statement, Int32(index + 1), chatID)
                }
                bind(effectiveStartDate, to: statement, index: Int32(dateParameter))

                while sqlite3_step(statement) == SQLITE_ROW {
                    let guid = text(statement, column: 1)
                    let isCurrentUser = sqlite3_column_int(statement, 2) == 1
                    let handle = text(statement, column: 3)
                    let participantKey = isCurrentUser ? "current-user" : handle
                    messageCounts[participantKey, default: 0] += 1
                    participantIdentity[participantKey] = (handle, isCurrentUser)
                    if !guid.isEmpty {
                        participantByGUID[guid] = participantKey
                    }
                }
                try checkCompletion(of: statement, in: database)
            }

            let reactionsSQL = """
                SELECT
                    r.ROWID,
                    COALESCE(r.associated_message_guid, ''),
                    r.associated_message_type
                FROM chat_message_join cmj
                JOIN message r ON r.ROWID = cmj.message_id
                WHERE cmj.chat_id IN (\(placeholders))
                    AND (
                        r.associated_message_type BETWEEN 2000 AND 2005
                        OR r.associated_message_type BETWEEN 3000 AND 3005
                    )
                GROUP BY r.ROWID
                """

            var reactionNet: [ReactionTarget: Int] = [:]
            do {
                let statement = try prepare(reactionsSQL, in: database)
                defer { sqlite3_finalize(statement) }
                for (index, chatID) in chatIDs.enumerated() {
                    sqlite3_bind_int64(statement, Int32(index + 1), chatID)
                }

                while sqlite3_step(statement) == SQLITE_ROW {
                    let associatedGUID = text(statement, column: 1)
                    let messageGUID = associatedGUID.split(separator: "/").last.map(String.init)
                        ?? associatedGUID
                    guard participantByGUID[messageGUID] != nil else { continue }

                    let rawType = Int(sqlite3_column_int(statement, 2))
                    let typeValue = rawType >= 3000 ? rawType - 3000 : rawType - 2000
                    guard let type = ReactionType(rawValue: typeValue), type != .all else {
                        continue
                    }
                    let delta = rawType >= 3000 ? -1 : 1
                    reactionNet[
                        ReactionTarget(messageGUID: messageGUID, type: type),
                        default: 0
                    ] += delta
                }
                try checkCompletion(of: statement, in: database)
            }

            var reactionsByParticipant: [String: [ReactionType: Int]] = [:]
            for (target, netCount) in reactionNet where netCount > 0 {
                guard let participantKey = participantByGUID[target.messageGUID] else {
                    continue
                }
                reactionsByParticipant[participantKey, default: [:]][target.type, default: 0] += netCount
            }

            return messageCounts.compactMap { participantKey, messageCount in
                guard let identity = participantIdentity[participantKey] else { return nil }
                return RawParticipantStats(
                    handle: identity.handle,
                    isCurrentUser: identity.isCurrentUser,
                    messageCount: messageCount,
                    reactionMessageCount: messageCount,
                    reactionsByType: reactionsByParticipant[participantKey, default: [:]],
                    reactionsGivenByType: [:]
                )
            }
        }
    }

}
