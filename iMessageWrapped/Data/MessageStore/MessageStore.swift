import Foundation

// MARK: - Stored message types

nonisolated struct ReactionTarget: Hashable {
    let messageGUID: String
    let type: ReactionType
}

nonisolated struct StoredMessage {
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

nonisolated struct ActiveReactionKey: Hashable {
    let targetGUID: String
    let type: ReactionType
    let giver: String
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
    let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

}
