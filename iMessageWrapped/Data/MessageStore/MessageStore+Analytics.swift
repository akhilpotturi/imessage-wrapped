import Foundation

// MARK: - In-memory analytics

private nonisolated struct ActiveReaction {
    let key: ActiveReactionKey
    let target: StoredMessage
}

extension MessageStore {
    func aggregate(
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

}
