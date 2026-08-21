import Foundation
import SQLite3

private nonisolated struct ReactionTarget: Hashable {
    let messageGUID: String
    let type: ReactionType
}

private nonisolated struct StoredMessage {
    let id: Int64
    let guid: String
    let date: Date
    let isFromMe: Bool
    let handle: String
    let itemType: Int
    let associatedType: Int
    let associatedGUID: String
    let text: String
    let hasAttachment: Bool

    var participantKey: String { isFromMe ? "ME" : handle }
    var isReaction: Bool {
        (2000...2005).contains(associatedType) || (3000...3005).contains(associatedType)
    }
}

private nonisolated struct ActiveReactionKey: Hashable {
    let targetGUID: String
    let type: ReactionType
    let giver: String
}

private nonisolated struct ActiveReaction {
    let key: ActiveReactionKey
    let target: StoredMessage
}

enum MessageStoreError: LocalizedError {
    case databaseUnavailable
    case databaseOpenFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            "The Messages database is unavailable. Grant Full Disk Access and relaunch the app."
        case .databaseOpenFailed(let message):
            "Could not open the Messages database: \(message)"
        case .queryFailed(let message):
            "Could not read Messages data: \(message)"
        }
    }
}

actor MessageStore {
    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

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

    private func aggregate(
        events: [StoredMessage],
        filters: ConversationFilters
    ) -> FilteredConversationData {
        let baseMessages = events.filter { !$0.isReaction }
        var targetByGUID: [String: StoredMessage] = [:]
        for message in baseMessages where !message.guid.isEmpty {
            targetByGUID[message.guid] = message
        }

        let filteredMessages = baseMessages.filter {
            messageMatches($0, filters: filters)
        }
        let activeReactions = activeReactions(
            from: events.filter(\.isReaction),
            targets: targetByGUID,
            filters: filters
        )
        let reactionEligibleMessages = baseMessages.filter {
            reactionTargetMatches($0, filters: filters)
        }

        let includedMessages = filters.scope == .reactions ? [] : filteredMessages
        let includedReactions = filters.scope == .messages ? [] : activeReactions

        let total = includedMessages.count + includedReactions.count
        let sent = includedMessages.filter(\.isFromMe).count
            + includedReactions.filter { $0.key.giver == "ME" }.count
        let received = includedMessages.filter { !$0.isFromMe }.count
            + includedReactions.filter { $0.target.isFromMe }.count
        let latestDate = (
            includedMessages.map(\.date) + includedReactions.map(\.target.date)
        ).max()

        var daily: [Date: (sent: Int, received: Int)] = [:]
        let calendar = Calendar.current
        for message in includedMessages {
            let day = calendar.startOfDay(for: message.date)
            if message.isFromMe {
                daily[day, default: (0, 0)].sent += 1
            } else {
                daily[day, default: (0, 0)].received += 1
            }
        }
        for reaction in includedReactions {
            let day = calendar.startOfDay(for: reaction.target.date)
            if reaction.key.giver == "ME" {
                daily[day, default: (0, 0)].sent += 1
            } else {
                daily[day, default: (0, 0)].received += 1
            }
        }

        var participantMessages: [String: Int] = [:]
        var reactionMessageCounts: [String: Int] = [:]
        var participantIdentity: [String: (handle: String, isCurrentUser: Bool)] = [:]
        for message in filteredMessages {
            participantMessages[message.participantKey, default: 0] += 1
            participantIdentity[message.participantKey] = (
                message.participantKey,
                message.isFromMe
            )
        }
        for message in reactionEligibleMessages {
            reactionMessageCounts[message.participantKey, default: 0] += 1
            participantIdentity[message.participantKey] = (
                message.participantKey,
                message.isFromMe
            )
        }

        var participantReactions: [String: [ReactionType: Int]] = [:]
        var participantReactionsGiven: [String: [ReactionType: Int]] = [:]
        var reactionEdges: [String: Int] = [:]
        for reaction in activeReactions {
            let receiver = reaction.target.participantKey
            participantIdentity[receiver] = (receiver, reaction.target.isFromMe)
            participantIdentity[reaction.key.giver] = (
                reaction.key.giver,
                reaction.key.giver == "ME"
            )
            participantReactions[receiver, default: [:]][reaction.key.type, default: 0] += 1
            participantReactionsGiven[reaction.key.giver, default: [:]][reaction.key.type, default: 0] += 1
            reactionEdges["\(reaction.key.giver)\u{1f}\(receiver)", default: 0] += 1
        }

        let participantKeys = Set(participantIdentity.keys)
        let stats = participantKeys.compactMap { key -> RawParticipantStats? in
            guard let identity = participantIdentity[key] else { return nil }
            return RawParticipantStats(
                handle: identity.handle,
                isCurrentUser: identity.isCurrentUser,
                messageCount: participantMessages[key, default: 0],
                reactionMessageCount: reactionMessageCounts[key, default: 0],
                reactionsByType: participantReactions[key, default: [:]],
                reactionsGivenByType: participantReactionsGiven[key, default: [:]]
            )
        }

        return FilteredConversationData(
            aggregate: MessageAggregate(
                messageCount: total,
                sentCount: sent,
                receivedCount: received,
                lastMessageDate: latestDate
            ),
            dailyActivity: daily.map {
                DailyMessageCount(date: $0.key, sent: $0.value.sent, received: $0.value.received)
            }.sorted { $0.date < $1.date },
            participantStats: stats
            ,
            reactionEdges: reactionEdges.compactMap { key, count in
                let participants = key.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard participants.count == 2 else { return nil }
                return RawReactionEdge(
                    giverHandle: String(participants[0]),
                    receiverHandle: String(participants[1]),
                    count: count
                )
            }
        )
    }

    private func messageMatches(
        _ message: StoredMessage,
        filters: ConversationFilters
    ) -> Bool {
        if let startDate = filters.range.startDate, message.date < startDate {
            return false
        }
        if !filters.includeSystemEvents, message.itemType != 0 {
            return false
        }
        switch filters.content {
        case .all:
            break
        case .text:
            guard !message.text.isEmpty, !message.hasAttachment else { return false }
        case .attachments:
            guard message.hasAttachment else { return false }
        }
        switch filters.direction {
        case .all:
            break
        case .sent:
            guard message.isFromMe else { return false }
        case .received:
            guard !message.isFromMe else { return false }
        }
        return handlesMatch(
            participant: message.participantKey,
            selectedHandles: filters.senderHandles
        )
    }

    private func activeReactions(
        from events: [StoredMessage],
        targets: [String: StoredMessage],
        filters: ConversationFilters
    ) -> [ActiveReaction] {
        var counts: [ActiveReactionKey: Int] = [:]

        for event in events {
            let targetGUID = event.associatedGUID.split(separator: "/").last.map(String.init)
                ?? event.associatedGUID
            guard let target = targets[targetGUID] else { continue }
            guard reactionTargetMatches(target, filters: filters) else { continue }

            let rawType = event.associatedType
            let typeValue = rawType >= 3000 ? rawType - 3000 : rawType - 2000
            guard let type = ReactionType(rawValue: typeValue), type != .all else {
                continue
            }

            if filters.reactionType != .all, filters.reactionType != type {
                continue
            }
            guard handlesMatch(
                participant: event.participantKey,
                selectedHandles: filters.reactionGiverHandles
            ), handlesMatch(
                participant: target.participantKey,
                selectedHandles: filters.reactionReceiverHandles
            ) else {
                continue
            }

            let key = ActiveReactionKey(
                targetGUID: targetGUID,
                type: type,
                giver: event.participantKey
            )
            counts[key, default: 0] += rawType >= 3000 ? -1 : 1
        }

        return counts.compactMap { key, count in
            guard count > 0, let target = targets[key.targetGUID] else { return nil }
            return ActiveReaction(key: key, target: target)
        }
    }

    private func reactionTargetMatches(
        _ message: StoredMessage,
        filters: ConversationFilters
    ) -> Bool {
        if let startDate = filters.range.startDate, message.date < startDate {
            return false
        }
        return handlesMatch(
            participant: message.participantKey,
            selectedHandles: filters.reactionReceiverHandles
        )
    }

    private func handlesMatch(
        participant: String,
        selectedHandles: [String]
    ) -> Bool {
        selectedHandles.isEmpty || selectedHandles.contains(participant)
    }

    private func withDatabase<T>(
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

    private func prepare(
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

    private func chatColumns(in database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(chat)", in: database)
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(text(statement, column: 1))
        }
        return columns
    }

    private func messageFilterClause(_ filters: ConversationFilters) -> String {
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

    private func bind(_ date: Date?, to statement: OpaquePointer, index: Int32) {
        if let date {
            sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func appleDate(from value: Int64) -> Date? {
        guard value != 0 else { return nil }
        let seconds = abs(value) > 100_000_000_000
            ? Double(value) / 1_000_000_000
            : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func checkCompletion(
        of statement: OpaquePointer,
        in database: OpaquePointer
    ) throws {
        let result = sqlite3_errcode(database)
        guard result == SQLITE_OK || result == SQLITE_DONE else {
            throw MessageStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}
