import Foundation

enum AnalyticsRange: String, CaseIterable, Identifiable, Sendable {
    case thirtyDays
    case sixMonths
    case oneYear
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtyDays: "30 days"
        case .sixMonths: "6 months"
        case .oneYear: "1 year"
        case .allTime: "All time"
        }
    }

    nonisolated var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -30, to: .now)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: .now)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: .now)
        case .allTime:
            return nil
        }
    }
}

enum MessageContentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case attachments

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All content"
        case .text: "Text only"
        case .attachments: "Attachments"
        }
    }
}

enum ActivityScope: String, CaseIterable, Identifiable, Sendable {
    case messages
    case reactions
    case both

    var id: Self { self }

    var title: String {
        switch self {
        case .messages: "Messages"
        case .reactions: "Reactions"
        case .both: "Both"
        }
    }

    var systemImage: String {
        switch self {
        case .messages: "message.fill"
        case .reactions: "heart.fill"
        case .both: "sparkles"
        }
    }
}

enum MessageDirectionFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case sent
    case received

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "Both directions"
        case .sent: "Sent"
        case .received: "Received"
        }
    }
}

enum AnalyticsPreset: String, CaseIterable, Identifiable {
    case everything
    case messages
    case sentByMe
    case attachments

    var id: Self { self }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .messages: "Messages"
        case .sentByMe: "Sent by me"
        case .attachments: "Attachments"
        }
    }

    var systemImage: String {
        switch self {
        case .everything: "sparkles"
        case .messages: "message.fill"
        case .sentByMe: "paperplane.fill"
        case .attachments: "photo.on.rectangle.angled"
        }
    }
}

struct ConversationFilters: Equatable, Sendable {
    var range: AnalyticsRange = .allTime
    var scope: ActivityScope = .both
    var content: MessageContentFilter = .all
    var direction: MessageDirectionFilter = .all
    var senderHandles: [String] = []
    var reactionType: ReactionType = .all
    var reactionGiverHandles: [String] = []
    var reactionReceiverHandles: [String] = []
    var includeSystemEvents = false

    static let defaultFilters = ConversationFilters()
}

struct SenderFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let handles: [String]
    let isCurrentUser: Bool
}

enum ConversationKind: String, Sendable {
    case direct
    case group
}

struct ConversationSummary: Identifiable, Hashable, Sendable {
    let id: String
    let chatIDs: [Int64]
    let title: String
    let kind: ConversationKind
    let participantIdentifiers: [String]
    let lineageIdentifiers: [String]
    let messageCount: Int
    let sentCount: Int
    let receivedCount: Int
    let lastMessageDate: Date?
}

struct MessageAggregate: Sendable {
    let messageCount: Int
    let sentCount: Int
    let receivedCount: Int
    let lastMessageDate: Date?
}

struct DailyMessageCount: Identifiable, Hashable, Sendable {
    let date: Date
    let sent: Int
    let received: Int

    var id: Date { date }
    var total: Int { sent + received }
}

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case messagesSent
    case reactionsReceived
    case reactionsGiven
    case messagesAndReactions
    case reactionsPerMessage

    var id: Self { self }

    var title: String {
        switch self {
        case .messagesSent: "Most messages sent"
        case .reactionsReceived: "Most reactions received"
        case .reactionsGiven: "Most reactions given"
        case .messagesAndReactions: "Messages + reactions"
        case .reactionsPerMessage: "Reactions per message"
        }
    }
}

enum ReactionType: Int, CaseIterable, Identifiable, Sendable {
    case all = -1
    case loved = 0
    case liked = 1
    case disliked = 2
    case laughed = 3
    case emphasized = 4
    case questioned = 5

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All reactions"
        case .loved: "Loved"
        case .liked: "Liked"
        case .disliked: "Disliked"
        case .laughed: "Laughed"
        case .emphasized: "Emphasized"
        case .questioned: "Questioned"
        }
    }

    var symbol: String {
        switch self {
        case .all: "✨"
        case .loved: "❤️"
        case .liked: "👍"
        case .disliked: "👎"
        case .laughed: "😂"
        case .emphasized: "‼️"
        case .questioned: "❓"
        }
    }
}

struct RawParticipantStats: Sendable {
    let handle: String
    let isCurrentUser: Bool
    let messageCount: Int
    let reactionMessageCount: Int
    let reactionsByType: [ReactionType: Int]
    let reactionsGivenByType: [ReactionType: Int]
}

struct RawReactionEdge: Sendable {
    let giverHandle: String
    let receiverHandle: String
    let count: Int
}

struct ReactionDynamicsEdge: Identifiable, Sendable {
    let giverID: String
    let giverName: String
    let receiverID: String
    let receiverName: String
    let count: Int

    var id: String { "\(giverID)->\(receiverID)" }
}

struct ParticipantLeaderboardEntry: Identifiable, Sendable {
    let id: String
    let displayName: String
    let isCurrentUser: Bool
    let rawHandles: [String]
    let messageCount: Int
    let reactionMessageCount: Int
    let reactionsByType: [ReactionType: Int]
    let reactionsGivenByType: [ReactionType: Int]

    func reactionCount(for type: ReactionType) -> Int {
        if type == .all {
            return reactionsByType.values.reduce(0, +)
        }
        return reactionsByType[type, default: 0]
    }

    func reactionRate(for type: ReactionType) -> Double {
        guard reactionMessageCount > 0 else { return 0 }
        return Double(reactionCount(for: type)) / Double(reactionMessageCount)
    }

    func reactionsGiven(for type: ReactionType) -> Int {
        if type == .all {
            return reactionsGivenByType.values.reduce(0, +)
        }
        return reactionsGivenByType[type, default: 0]
    }
}

struct ConversationAnalytics: Sendable {
    let summary: ConversationSummary
    let dailyActivity: [DailyMessageCount]
    let leaderboard: [ParticipantLeaderboardEntry]
    let reactionDynamics: [ReactionDynamicsEdge]
    let currentUserName: String
}

struct FilteredConversationData: Sendable {
    let aggregate: MessageAggregate
    let dailyActivity: [DailyMessageCount]
    let participantStats: [RawParticipantStats]
    let reactionEdges: [RawReactionEdge]
}

enum SidebarSelection: Hashable {
    case overview
    case conversation(String)
}
