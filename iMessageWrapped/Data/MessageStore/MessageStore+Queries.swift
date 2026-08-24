import Foundation
import SQLite3

// MARK: - Conversation queries

extension MessageStore {
    func loadFilteredConversationData(
        chatIDs: [Int64],
        filters: ConversationFilters
    ) throws -> FilteredConversationData {
        guard !chatIDs.isEmpty else {
            return FilteredConversationData(
                aggregate: MessageAggregate(
                    messageCount: 0,
                    sentCount: 0,
                    receivedCount: 0,
                    lastMessageDate: nil
                ),
                dailyActivity: [],
                participantStats: [],
                reactionEdges: []
            )
        }

        return try withDatabase { database in
            let placeholders = chatIDs.indices.map { "?\($0 + 1)" }.joined(separator: ",")
            let sql = """
                SELECT
                    m.ROWID,
                    COALESCE(m.guid, ''),
                    m.date,
                    m.is_from_me,
                    COALESCE(h.id, 'Unknown'),
                    COALESCE(m.item_type, 0),
                    COALESCE(m.associated_message_type, 0),
                    COALESCE(m.associated_message_guid, ''),
                    COALESCE(m.text, ''),
                    EXISTS (
                        SELECT 1
                        FROM message_attachment_join maj
                        WHERE maj.message_id = m.ROWID
                    )
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

            var events: [StoredMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let date = appleDate(from: sqlite3_column_int64(statement, 2)) else {
                    continue
                }
                events.append(
                    StoredMessage(
                        id: sqlite3_column_int64(statement, 0),
                        guid: text(statement, column: 1),
                        date: date,
                        isFromMe: sqlite3_column_int(statement, 3) == 1,
                        handle: text(statement, column: 4),
                        itemType: Int(sqlite3_column_int(statement, 5)),
                        associatedType: Int(sqlite3_column_int(statement, 6)),
                        associatedGUID: text(statement, column: 7),
                        text: text(statement, column: 8),
                        hasAttachment: sqlite3_column_int(statement, 9) == 1
                    )
                )
            }
            try checkCompletion(of: statement, in: database)
            return aggregate(events: events, filters: filters)
        }
    }

    func loadMoverStats(
        chatIDs: [Int64],
        responseWindow: TimeInterval,
        responseFilter: MoverResponseFilter,
        responderContext: MoverResponderContext,
        lookbackWindow: TimeInterval,
        since startDate: Date?
    ) throws -> [RawMoverStats] {
        guard !chatIDs.isEmpty, responseWindow > 0, lookbackWindow > 0 else { return [] }

        return try withDatabase { database in
            let placeholders = chatIDs.indices.map { "?\($0 + 1)" }.joined(separator: ",")
            let sql = """
                SELECT
                    m.date,
                    m.is_from_me,
                    CASE
                        WHEN m.is_from_me = 1 THEN 'ME'
                        ELSE COALESCE(h.id, 'Unknown')
                    END,
                    COALESCE(m.guid, ''),
                    COALESCE(m.item_type, 0),
                    COALESCE(m.associated_message_type, 0),
                    COALESCE(m.associated_message_guid, '')
                FROM chat_message_join cmj
                JOIN message m ON m.ROWID = cmj.message_id
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                WHERE cmj.chat_id IN (\(placeholders))
                GROUP BY m.ROWID
                ORDER BY m.date, m.ROWID
                """
            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            for (index, chatID) in chatIDs.enumerated() {
                sqlite3_bind_int64(statement, Int32(index + 1), chatID)
            }

            var events: [(
                date: Date,
                participant: String,
                isCurrentUser: Bool,
                guid: String,
                itemType: Int,
                associatedType: Int,
                associatedGUID: String
            )] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let date = appleDate(from: sqlite3_column_int64(statement, 0)) else {
                    continue
                }
                let isCurrentUser = sqlite3_column_int(statement, 1) == 1
                events.append(
                    (
                        date: date,
                        participant: isCurrentUser ? "ME" : text(statement, column: 2),
                        isCurrentUser: isCurrentUser,
                        guid: text(statement, column: 3),
                        itemType: Int(sqlite3_column_int(statement, 4)),
                        associatedType: Int(sqlite3_column_int(statement, 5)),
                        associatedGUID: text(statement, column: 6)
                    )
                )
            }
            try checkCompletion(of: statement, in: database)

            let messages = events.filter { event in
                event.itemType == 0
                    && !((2000...2005).contains(event.associatedType)
                        || (3000...3005).contains(event.associatedType))
            }
            var activeReactionDates: [ActiveReactionKey: [Date]] = [:]
            for event in events {
                let rawType = event.associatedType
                guard (2000...2005).contains(rawType) || (3000...3005).contains(rawType)
                else {
                    continue
                }
                let targetGUID = event.associatedGUID.split(separator: "/").last.map(String.init)
                    ?? event.associatedGUID
                let typeValue = rawType >= 3000 ? rawType - 3000 : rawType - 2000
                guard let type = ReactionType(rawValue: typeValue), !targetGUID.isEmpty else {
                    continue
                }
                let key = ActiveReactionKey(
                    targetGUID: targetGUID,
                    type: type,
                    giver: event.participant
                )
                if rawType >= 3000 {
                    _ = activeReactionDates[key]?.popLast()
                } else {
                    activeReactionDates[key, default: []].append(event.date)
                }
            }
            var reactionsByTarget: [String: [(participant: String, date: Date)]] = [:]
            for (key, dates) in activeReactionDates {
                for date in dates {
                    reactionsByTarget[key.targetGUID, default: []].append(
                        (participant: key.giver, date: date)
                    )
                }
            }

            var messageCounts: [String: Int] = [:]
            var responderTotals: [String: Int] = [:]
            var followUpMessageTotals: [String: Int] = [:]
            var identities: [String: Bool] = [:]
            var respondersInWindow: [String: Int] = [:]
            var activeBefore: [String: Int] = [:]
            var lookbackStart = 0
            var windowEnd = min(1, messages.count)

            for index in messages.indices {
                let message = messages[index]
                let lookbackCutoff = message.date.addingTimeInterval(-lookbackWindow)
                while lookbackStart < index,
                      messages[lookbackStart].date < lookbackCutoff {
                    let participant = messages[lookbackStart].participant
                    let remaining = activeBefore[participant, default: 0] - 1
                    if remaining > 0 {
                        activeBefore[participant] = remaining
                    } else {
                        activeBefore.removeValue(forKey: participant)
                    }
                    lookbackStart += 1
                }

                if windowEnd < index + 1 {
                    windowEnd = index + 1
                }

                let cutoff = message.date.addingTimeInterval(responseWindow)
                while windowEnd < messages.count, messages[windowEnd].date <= cutoff {
                    respondersInWindow[messages[windowEnd].participant, default: 0] += 1
                    windowEnd += 1
                }

                var responders: Set<String> = []
                if responseFilter != .reactions {
                    responders.formUnion(respondersInWindow.keys)
                }
                if responseFilter != .messages {
                    let reactionResponders = reactionsByTarget[message.guid, default: []]
                        .filter { $0.date >= message.date && $0.date <= cutoff }
                        .map(\.participant)
                    responders.formUnion(reactionResponders)
                }
                responders.remove(message.participant)
                responders = Set(responders.filter {
                    responderMatchesContext(
                        $0,
                        activeBefore: activeBefore,
                        context: responderContext
                    )
                })

                let isInRange = startDate.map { message.date >= $0 } ?? true
                if isInRange {
                    messageCounts[message.participant, default: 0] += 1
                    responderTotals[message.participant, default: 0] += responders.count
                    followUpMessageTotals[message.participant, default: 0] += respondersInWindow
                        .filter {
                            $0.key != message.participant
                                && responderMatchesContext(
                                    $0.key,
                                    activeBefore: activeBefore,
                                    context: responderContext
                                )
                        }
                        .values
                        .reduce(0, +)
                    identities[message.participant] = message.isCurrentUser
                }

                let nextIndex = index + 1
                if nextIndex < windowEnd {
                    let nextParticipant = messages[nextIndex].participant
                    let remaining = respondersInWindow[nextParticipant, default: 0] - 1
                    if remaining > 0 {
                        respondersInWindow[nextParticipant] = remaining
                    } else {
                        respondersInWindow.removeValue(forKey: nextParticipant)
                    }
                }
                activeBefore[message.participant, default: 0] += 1
            }

            return messageCounts.map { participant, count in
                RawMoverStats(
                    handle: participant,
                    isCurrentUser: identities[participant] ?? false,
                    messageCount: count,
                    totalResponders: responderTotals[participant, default: 0],
                    totalFollowUpMessages: followUpMessageTotals[participant, default: 0]
                )
            }
        }
    }

    private func responderMatchesContext(
        _ participant: String,
        activeBefore: [String: Int],
        context: MoverResponderContext
    ) -> Bool {
        switch context {
        case .all:
            return true
        case .newlyActivated:
            return activeBefore[participant, default: 0] == 0
        case .alreadyActive:
            return activeBefore[participant, default: 0] > 0
        }
    }

    func loadConversations(since startDate: Date?) throws -> [ConversationSummary] {
        return try withDatabase { database in
            let availableColumns = try chatColumns(in: database)
            let lineageColumns = ["guid", "group_id", "original_group_id"]
                .filter(availableColumns.contains)
            let lineageSelection = lineageColumns.isEmpty
                ? "''"
                : lineageColumns
                    .map { "COALESCE(NULLIF(c.\($0), ''), '')" }
                    .joined(separator: ",\n                    ")
            let sql = """
                WITH message_stats AS (
                    SELECT
                        cmj.chat_id,
                        COUNT(*) AS message_count,
                        SUM(CASE WHEN m.is_from_me = 1 THEN 1 ELSE 0 END) AS sent_count,
                        SUM(CASE WHEN m.is_from_me = 0 THEN 1 ELSE 0 END) AS received_count,
                        MAX(m.date) AS last_message_date
                    FROM chat_message_join cmj
                    JOIN message m ON m.ROWID = cmj.message_id
                    WHERE (?1 IS NULL OR (
                        CASE
                            WHEN ABS(m.date) > 100000000000
                                THEN (m.date / 1000000000.0) + 978307200
                            ELSE m.date + 978307200
                        END
                    ) >= ?1)
                    GROUP BY cmj.chat_id
                ),
                participant_stats AS (
                    SELECT
                        chj.chat_id,
                        COUNT(DISTINCT chj.handle_id) AS participant_count,
                        GROUP_CONCAT(h.id, char(31)) AS participant_ids
                    FROM chat_handle_join chj
                    JOIN handle h ON h.ROWID = chj.handle_id
                    GROUP BY chj.chat_id
                )
                SELECT
                    c.ROWID,
                    COALESCE(NULLIF(c.display_name, ''), ''),
                    COALESCE(NULLIF(c.chat_identifier, ''), ''),
                    COALESCE(ps.participant_count, 0),
                    COALESCE(ps.participant_ids, ''),
                    COALESCE(ms.message_count, 0),
                    COALESCE(ms.sent_count, 0),
                    COALESCE(ms.received_count, 0),
                    ms.last_message_date,
                    \(lineageSelection)
                FROM chat c
                LEFT JOIN message_stats ms ON ms.chat_id = c.ROWID
                LEFT JOIN participant_stats ps ON ps.chat_id = c.ROWID
                ORDER BY COALESCE(ms.message_count, 0) DESC
                """

            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            bind(startDate, to: statement, index: 1)

            var conversations: [ConversationSummary] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let displayName = text(statement, column: 1)
                let chatIdentifier = text(statement, column: 2)
                let participantCount = Int(sqlite3_column_int(statement, 3))
                let identifiers = text(statement, column: 4)
                    .split(separator: "\u{1f}")
                    .map(String.init)
                let fallbackTitle = chatIdentifier.isEmpty
                    ? "Unknown conversation"
                    : chatIdentifier
                let title = displayName.isEmpty
                    ? identifiers.first ?? fallbackTitle
                    : displayName
                var lineageIdentifiers = lineageColumns.indices.compactMap { index -> String? in
                    let value = text(statement, column: Int32(9 + index))
                    return value.isEmpty ? nil : value
                }
                if participantCount > 1, !chatIdentifier.isEmpty {
                    lineageIdentifiers.append(chatIdentifier)
                }

                conversations.append(
                    ConversationSummary(
                        id: "chat:\(id)",
                        chatIDs: [id],
                        title: title,
                        kind: participantCount > 1 ? .group : .direct,
                        participantIdentifiers: identifiers,
                        lineageIdentifiers: lineageIdentifiers,
                        messageCount: Int(sqlite3_column_int64(statement, 5)),
                        sentCount: Int(sqlite3_column_int64(statement, 6)),
                        receivedCount: Int(sqlite3_column_int64(statement, 7)),
                        lastMessageDate: appleDate(from: sqlite3_column_int64(statement, 8))
                    )
                )
            }

            try checkCompletion(of: statement, in: database)
            return conversations
        }
    }

    func loadAggregate(
        chatIDs: [Int64],
        since startDate: Date?,
        filters: ConversationFilters? = nil
    ) throws -> MessageAggregate {
        guard !chatIDs.isEmpty else {
            return MessageAggregate(
                messageCount: 0,
                sentCount: 0,
                receivedCount: 0,
                lastMessageDate: nil
            )
        }

        return try withDatabase { database in
            let effectiveStartDate = filters?.range.startDate ?? startDate
            let filterClause = filters.map(messageFilterClause) ?? ""
            let placeholders = chatIDs.indices
                .map { "?\($0 + 1)" }
                .joined(separator: ",")
            let dateParameter = chatIDs.count + 1
            let sql = """
                SELECT
                    COUNT(DISTINCT m.ROWID),
                    COUNT(DISTINCT CASE WHEN m.is_from_me = 1 THEN m.ROWID END),
                    COUNT(DISTINCT CASE WHEN m.is_from_me = 0 THEN m.ROWID END),
                    MAX(m.date)
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
                """

            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            for (index, chatID) in chatIDs.enumerated() {
                sqlite3_bind_int64(statement, Int32(index + 1), chatID)
            }
            bind(effectiveStartDate, to: statement, index: Int32(dateParameter))

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
            }
            return MessageAggregate(
                messageCount: Int(sqlite3_column_int64(statement, 0)),
                sentCount: Int(sqlite3_column_int64(statement, 1)),
                receivedCount: Int(sqlite3_column_int64(statement, 2)),
                lastMessageDate: appleDate(from: sqlite3_column_int64(statement, 3))
            )
        }
    }

    func loadDailyActivity(
        chatIDs: [Int64],
        since startDate: Date?,
        filters: ConversationFilters? = nil
    ) throws -> [DailyMessageCount] {
        guard !chatIDs.isEmpty else { return [] }

        return try withDatabase { database in
            let effectiveStartDate = filters?.range.startDate ?? startDate
            let filterClause = filters.map(messageFilterClause) ?? ""
            let placeholders = chatIDs.indices
                .map { "?\($0 + 1)" }
                .joined(separator: ",")
            let dateParameter = chatIDs.count + 1
            let sql = """
                SELECT
                    date(
                        CASE
                            WHEN ABS(m.date) > 100000000000
                                THEN (m.date / 1000000000.0) + 978307200
                            ELSE m.date + 978307200
                        END,
                        'unixepoch',
                        'localtime'
                    ) AS activity_date,
                    COUNT(DISTINCT CASE WHEN m.is_from_me = 1 THEN m.ROWID END),
                    COUNT(DISTINCT CASE WHEN m.is_from_me = 0 THEN m.ROWID END)
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
                GROUP BY activity_date
                ORDER BY activity_date
                """

            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }
            for (index, chatID) in chatIDs.enumerated() {
                sqlite3_bind_int64(statement, Int32(index + 1), chatID)
            }
            bind(effectiveStartDate, to: statement, index: Int32(dateParameter))

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"

            var activity: [DailyMessageCount] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let date = formatter.date(from: text(statement, column: 0)) else {
                    continue
                }
                activity.append(
                    DailyMessageCount(
                        date: date,
                        sent: Int(sqlite3_column_int64(statement, 1)),
                        received: Int(sqlite3_column_int64(statement, 2))
                    )
                )
            }

            try checkCompletion(of: statement, in: database)
            return activity
        }
    }

}
