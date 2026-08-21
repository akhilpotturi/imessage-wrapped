import Contacts
import Foundation

struct ResolvedContact: Sendable {
    let identifier: String
    let displayName: String
}

enum ContactResolverError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Contacts access is required to replace phone numbers and email addresses with names."
    }
}

actor ContactResolver {
    private let store = CNContactStore()
    private var emailIndex: [String: ResolvedContact] = [:]
    private var phoneIndex: [String: ResolvedContact] = [:]
    private var hasBuiltIndex = false

    private struct GroupCandidate {
        let conversation: ConversationSummary
        let participantKeys: Set<String>
    }

    func resolveAndMerge(
        _ conversations: [ConversationSummary]
    ) async throws -> [ConversationSummary] {
        try await ensureAccess()
        try buildIndexIfNeeded()
        let currentUserName = try currentUserDisplayName()

        var directConversations: [String: ConversationSummary] = [:]
        var groupCandidates: [GroupCandidate] = []

        for conversation in conversations {
            let resolvedParticipants = conversation.participantIdentifiers.map(resolve)

            if conversation.kind == .group {
                var participantNames = uniqueNames(from: resolvedParticipants)
                if !participantNames.contains(currentUserName) {
                    participantNames.append(currentUserName)
                }
                let resolvedGroup = replacing(
                    conversation,
                    participantIdentifiers: participantNames
                )
                groupCandidates.append(
                    GroupCandidate(
                        conversation: resolvedGroup,
                        participantKeys: Set(resolvedParticipants.map(identityKey))
                    )
                )
                continue
            }

            let contactIDs = Set(resolvedParticipants.compactMap(\.contact?.identifier))
            let identityKey: String
            if contactIDs.count == 1, let contactID = contactIDs.first {
                identityKey = "contact:\(contactID)"
            } else {
                identityKey = "handle:\(normalizedHandle(conversation.participantIdentifiers.first ?? conversation.id))"
            }

            let names = uniqueNames(from: resolvedParticipants)
            let title = names.first ?? conversation.title
            let resolved = ConversationSummary(
                id: identityKey,
                chatIDs: conversation.chatIDs,
                title: title,
                kind: .direct,
                participantIdentifiers: names,
                lineageIdentifiers: conversation.lineageIdentifiers,
                messageCount: conversation.messageCount,
                sentCount: conversation.sentCount,
                receivedCount: conversation.receivedCount,
                lastMessageDate: conversation.lastMessageDate
            )

            if let existing = directConversations[identityKey] {
                directConversations[identityKey] = merge(existing, with: resolved)
            } else {
                directConversations[identityKey] = resolved
            }
        }

        return (Array(directConversations.values) + mergeGroups(groupCandidates))
            .sorted { $0.messageCount > $1.messageCount }
    }

    func resolveLeaderboard(
        _ stats: [RawParticipantStats]
    ) async throws -> [ParticipantLeaderboardEntry] {
        try await ensureAccess()
        try buildIndexIfNeeded()
        let myName = try currentUserDisplayName()
        var entries: [String: ParticipantLeaderboardEntry] = [:]

        for stat in stats {
            let resolved = resolve(stat.handle)
            let id: String
            let name: String
            if stat.isCurrentUser {
                id = "current-user"
                name = myName
            } else if let contact = resolved.contact {
                id = "contact:\(contact.identifier)"
                name = contact.displayName
            } else {
                id = "handle:\(normalizedHandle(stat.handle))"
                name = stat.handle
            }

            if let existing = entries[id] {
                var reactions = existing.reactionsByType
                for (type, count) in stat.reactionsByType {
                    reactions[type, default: 0] += count
                }
                var reactionsGiven = existing.reactionsGivenByType
                for (type, count) in stat.reactionsGivenByType {
                    reactionsGiven[type, default: 0] += count
                }
                entries[id] = ParticipantLeaderboardEntry(
                    id: id,
                    displayName: name,
                    isCurrentUser: stat.isCurrentUser,
                    rawHandles: Array(Set(existing.rawHandles + [stat.handle])).sorted(),
                    messageCount: existing.messageCount + stat.messageCount,
                    reactionMessageCount: existing.reactionMessageCount + stat.reactionMessageCount,
                    reactionsByType: reactions,
                    reactionsGivenByType: reactionsGiven
                )
            } else {
                entries[id] = ParticipantLeaderboardEntry(
                    id: id,
                    displayName: name,
                    isCurrentUser: stat.isCurrentUser,
                    rawHandles: [stat.handle],
                    messageCount: stat.messageCount,
                    reactionMessageCount: stat.reactionMessageCount,
                    reactionsByType: stat.reactionsByType,
                    reactionsGivenByType: stat.reactionsGivenByType
                )
            }
        }

        return Array(entries.values)
    }

    func currentUserDisplayName() throws -> String {
        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey
        ] as [CNKeyDescriptor]
        let contact = try store.unifiedMeContactWithKeys(toFetch: keys)
        return Self.displayName(for: contact)
    }

    func resolveReactionDynamics(
        _ edges: [RawReactionEdge]
    ) async throws -> [ReactionDynamicsEdge] {
        try await ensureAccess()
        try buildIndexIfNeeded()
        let myName = try currentUserDisplayName()
        var merged: [String: ReactionDynamicsEdge] = [:]

        for edge in edges {
            let giver = resolvedIdentity(for: edge.giverHandle, myName: myName)
            let receiver = resolvedIdentity(for: edge.receiverHandle, myName: myName)
            let key = "\(giver.id)->\(receiver.id)"

            if let existing = merged[key] {
                merged[key] = ReactionDynamicsEdge(
                    giverID: giver.id,
                    giverName: giver.name,
                    receiverID: receiver.id,
                    receiverName: receiver.name,
                    count: existing.count + edge.count
                )
            } else {
                merged[key] = ReactionDynamicsEdge(
                    giverID: giver.id,
                    giverName: giver.name,
                    receiverID: receiver.id,
                    receiverName: receiver.name,
                    count: edge.count
                )
            }
        }

        return Array(merged.values)
    }

    private func resolvedIdentity(
        for handle: String,
        myName: String
    ) -> (id: String, name: String) {
        if handle == "ME" {
            return ("current-user", myName)
        }
        let resolved = resolve(handle)
        if let contact = resolved.contact {
            return ("contact:\(contact.identifier)", contact.displayName)
        }
        return ("handle:\(normalizedHandle(handle))", handle)
    }

    private func ensureAccess() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return
        case .notDetermined:
            guard try await store.requestAccess(for: .contacts) else {
                throw ContactResolverError.accessDenied
            }
        case .denied, .restricted:
            throw ContactResolverError.accessDenied
        @unknown default:
            throw ContactResolverError.accessDenied
        }
    }

    private func buildIndexIfNeeded() throws {
        guard !hasBuiltIndex else { return }

        let keys = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var emails: [String: ResolvedContact] = [:]
        var phones: [String: ResolvedContact] = [:]

        try store.enumerateContacts(with: request) { contact, _ in
            let name = Self.displayName(for: contact)
            let resolved = ResolvedContact(
                identifier: contact.identifier,
                displayName: name
            )

            for email in contact.emailAddresses {
                let key = String(email.value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty {
                    emails[key] = resolved
                }
            }

            for phone in contact.phoneNumbers {
                let key = Self.normalizedPhone(phone.value.stringValue)
                if !key.isEmpty {
                    phones[key] = resolved
                }
            }
        }

        emailIndex = emails
        phoneIndex = phones
        hasBuiltIndex = true
    }

    private func resolve(_ handle: String) -> (raw: String, contact: ResolvedContact?) {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") {
            return (trimmed, emailIndex[trimmed.lowercased()])
        }
        return (trimmed, phoneIndex[Self.normalizedPhone(trimmed)])
    }

    private func uniqueNames(
        from participants: [(raw: String, contact: ResolvedContact?)]
    ) -> [String] {
        var seen: Set<String> = []
        return participants.compactMap { participant in
            let name = participant.contact?.displayName ?? participant.raw
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    private func replacing(
        _ conversation: ConversationSummary,
        id: String? = nil,
        participantIdentifiers: [String]
    ) -> ConversationSummary {
        ConversationSummary(
            id: id ?? conversation.id,
            chatIDs: conversation.chatIDs,
            title: conversation.title,
            kind: conversation.kind,
            participantIdentifiers: participantIdentifiers,
            lineageIdentifiers: conversation.lineageIdentifiers,
            messageCount: conversation.messageCount,
            sentCount: conversation.sentCount,
            receivedCount: conversation.receivedCount,
            lastMessageDate: conversation.lastMessageDate
        )
    }

    private func merge(
        _ first: ConversationSummary,
        with second: ConversationSummary
    ) -> ConversationSummary {
        ConversationSummary(
            id: first.id,
            chatIDs: Array(Set(first.chatIDs + second.chatIDs)).sorted(),
            title: first.title,
            kind: first.kind,
            participantIdentifiers: Array(
                Set(first.participantIdentifiers + second.participantIdentifiers)
            ).sorted(),
            lineageIdentifiers: Array(
                Set(first.lineageIdentifiers + second.lineageIdentifiers)
            ).sorted(),
            messageCount: first.messageCount + second.messageCount,
            sentCount: first.sentCount + second.sentCount,
            receivedCount: first.receivedCount + second.receivedCount,
            lastMessageDate: [first.lastMessageDate, second.lastMessageDate]
                .compactMap { $0 }
                .max()
        )
    }

    private func normalizedHandle(_ handle: String) -> String {
        handle.contains("@")
            ? handle.lowercased()
            : Self.normalizedPhone(handle)
    }

    private func identityKey(
        for participant: (raw: String, contact: ResolvedContact?)
    ) -> String {
        if let contact = participant.contact {
            return "contact:\(contact.identifier)"
        }
        return "handle:\(normalizedHandle(participant.raw))"
    }

    private func normalizedGroupName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedLineageIdentifier(_ identifier: String) -> String {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains(";"), let suffix = normalized.split(separator: ";").last {
            return String(suffix)
        }
        return normalized
    }

    private func mergeGroups(_ candidates: [GroupCandidate]) -> [ConversationSummary] {
        guard !candidates.isEmpty else { return [] }

        var parents = Array(candidates.indices)

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func join(_ first: Int, _ second: Int) {
            let firstRoot = root(of: first)
            let secondRoot = root(of: second)
            if firstRoot != secondRoot {
                parents[secondRoot] = firstRoot
            }
        }

        var lineageOwners: [String: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            for rawIdentifier in candidate.conversation.lineageIdentifiers {
                let identifier = normalizedLineageIdentifier(rawIdentifier)
                guard !identifier.isEmpty else { continue }
                if let owner = lineageOwners[identifier] {
                    join(index, owner)
                } else {
                    lineageOwners[identifier] = index
                }
            }
        }

        let nameBuckets = Dictionary(grouping: candidates.indices) {
            normalizedGroupName(candidates[$0].conversation.title)
        }
        for (name, indices) in nameBuckets where !name.isEmpty {
            for leftOffset in indices.indices {
                for rightOffset in indices.indices where rightOffset > leftOffset {
                    let left = indices[leftOffset]
                    let right = indices[rightOffset]
                    if hasStrongParticipantOverlap(
                        candidates[left].participantKeys,
                        candidates[right].participantKeys
                    ) {
                        join(left, right)
                    }
                }
            }
        }

        var mergedByRoot: [Int: ConversationSummary] = [:]
        for index in candidates.indices {
            let candidate = candidates[index].conversation
            let candidateRoot = root(of: index)
            if let existing = mergedByRoot[candidateRoot] {
                mergedByRoot[candidateRoot] = merge(existing, with: candidate)
            } else {
                mergedByRoot[candidateRoot] = candidate
            }
        }

        return mergedByRoot.values.map { conversation in
            replacing(
                conversation,
                id: "group:\(conversation.chatIDs.min() ?? 0)",
                participantIdentifiers: conversation.participantIdentifiers
            )
        }
    }

    private func hasStrongParticipantOverlap(
        _ first: Set<String>,
        _ second: Set<String>
    ) -> Bool {
        guard first.count >= 2, second.count >= 2 else { return false }
        let overlap = first.intersection(second).count
        guard overlap >= 2 else { return false }
        return Double(overlap) / Double(min(first.count, second.count)) >= 0.75
    }

    private static func normalizedPhone(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    private static func displayName(for contact: CNContact) -> String {
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty {
            return fullName
        }
        if !contact.nickname.isEmpty {
            return contact.nickname
        }
        return "Unnamed contact"
    }
}
