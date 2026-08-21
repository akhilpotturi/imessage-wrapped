import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var permissionGranted = Permissions.hasFullDiskAccessForMessagesDB()
    @Published var conversations: [ConversationSummary] = []
    @Published var selection: SidebarSelection? = .overview
    @Published var range: AnalyticsRange = .allTime
    @Published var conversationFilters = ConversationFilters.defaultFilters
    @Published var draftConversationFilters = ConversationFilters.defaultFilters
    @Published var senderOptions: [SenderFilterOption] = []
    @Published var selectedAnalytics: ConversationAnalytics?
    @Published var isLoading = false
    @Published var isLeaderboardLoading = false
    @Published var isDynamicsLoading = false
    @Published var loadingMessage = "Reading your Messages"
    @Published var errorMessage: String?
    @Published var contactWarning: String?

    private let messageStore = MessageStore(databaseURL: Permissions.messagesDBURL)
    private let contactResolver = ContactResolver()
    private var leaderboardFilterTask: Task<Void, Never>?
    private var dynamicsFilterTask: Task<Void, Never>?

    var directChats: [ConversationSummary] {
        conversations.filter { $0.kind == .direct }
    }

    var groupChats: [ConversationSummary] {
        conversations.filter { $0.kind == .group }
    }

    var totalMessages: Int {
        conversations.reduce(0) { $0 + $1.messageCount }
    }

    func refreshPermission() {
        permissionGranted = Permissions.hasFullDiskAccessForMessagesDB()
    }

    func load() async {
        refreshPermission()
        guard permissionGranted else { return }

        isLoading = true
        loadingMessage = "Reading your Messages"
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rawConversations = try await messageStore.loadConversations(since: range.startDate)
            loadingMessage = "Matching your contacts"
            do {
                conversations = try await contactResolver.resolveAndMerge(rawConversations)
                contactWarning = nil
            } catch {
                conversations = rawConversations
                contactWarning = error.localizedDescription
            }
            loadingMessage = "Removing duplicate messages"
            conversations = try await recountMergedConversations(conversations)
                .filter { $0.messageCount > 0 }
            loadingMessage = "Building your story"
            await loadSelectedConversation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recountMergedConversations(
        _ conversations: [ConversationSummary]
    ) async throws -> [ConversationSummary] {
        var recounted: [ConversationSummary] = []
        recounted.reserveCapacity(conversations.count)

        for conversation in conversations {
            guard conversation.chatIDs.count > 1 else {
                recounted.append(conversation)
                continue
            }

            let aggregate = try await messageStore.loadAggregate(
                chatIDs: conversation.chatIDs,
                since: range.startDate
            )
            recounted.append(
                ConversationSummary(
                    id: conversation.id,
                    chatIDs: conversation.chatIDs,
                    title: conversation.title,
                    kind: conversation.kind,
                    participantIdentifiers: conversation.participantIdentifiers,
                    lineageIdentifiers: conversation.lineageIdentifiers,
                    messageCount: aggregate.messageCount,
                    sentCount: aggregate.sentCount,
                    receivedCount: aggregate.receivedCount,
                    lastMessageDate: aggregate.lastMessageDate
                )
            )
        }

        return recounted.sorted { $0.messageCount > $1.messageCount }
    }

    func select(_ selection: SidebarSelection?) async {
        self.selection = selection
        guard case .conversation = selection else {
            selectedAnalytics = nil
            return
        }
        conversationFilters = .defaultFilters
        draftConversationFilters = .defaultFilters
        senderOptions = []
        isLoading = true
        loadingMessage = "Ranking the conversation"
        defer { isLoading = false }
        await loadSelectedConversation()
    }

    var hasPendingConversationFilters: Bool {
        draftConversationFilters != conversationFilters
    }

    func scheduleConversationAnalysis(_ filters: ConversationFilters) {
        draftConversationFilters = filters
        leaderboardFilterTask?.cancel()
        isLeaderboardLoading = true

        leaderboardFilterTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            conversationFilters = filters
            await loadSelectedConversation()
            guard !Task.isCancelled else { return }
            isLeaderboardLoading = false
        }
    }

    func scheduleDynamicsAnalysis(
        range: AnalyticsRange,
        reactionType: ReactionType
    ) {
        dynamicsFilterTask?.cancel()
        isDynamicsLoading = true
        dynamicsFilterTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await runDynamicsAnalysis(range: range, reactionType: reactionType)
            guard !Task.isCancelled else { return }
            isDynamicsLoading = false
        }
    }

    private func runDynamicsAnalysis(
        range: AnalyticsRange,
        reactionType: ReactionType
    ) async {
        guard case .conversation(let id) = selection,
              let summary = conversations.first(where: { $0.id == id }),
              let analytics = selectedAnalytics else {
            return
        }

        do {
            var filters = ConversationFilters.defaultFilters
            filters.scope = .reactions
            filters.range = range
            filters.reactionType = reactionType
            let data = try await messageStore.loadFilteredConversationData(
                chatIDs: summary.chatIDs,
                filters: filters
            )

            let dynamics: [ReactionDynamicsEdge]
            do {
                dynamics = try await contactResolver.resolveReactionDynamics(data.reactionEdges)
            } catch {
                dynamics = data.reactionEdges.map {
                    ReactionDynamicsEdge(
                        giverID: $0.giverHandle,
                        giverName: $0.giverHandle == "ME" ? "You" : $0.giverHandle,
                        receiverID: $0.receiverHandle,
                        receiverName: $0.receiverHandle == "ME" ? "You" : $0.receiverHandle,
                        count: $0.count
                    )
                }
            }

            selectedAnalytics = ConversationAnalytics(
                summary: analytics.summary,
                dailyActivity: analytics.dailyActivity,
                leaderboard: analytics.leaderboard,
                reactionDynamics: dynamics,
                currentUserName: analytics.currentUserName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSelectedConversation() async {
        guard case .conversation(let id) = selection,
              let summary = conversations.first(where: { $0.id == id }) else {
            selectedAnalytics = nil
            return
        }

        do {
            let overviewData = try await messageStore.loadFilteredConversationData(
                chatIDs: summary.chatIDs,
                filters: .defaultFilters
            )
            let data = try await messageStore.loadFilteredConversationData(
                chatIDs: summary.chatIDs,
                filters: conversationFilters
            )
            let filteredSummary = ConversationSummary(
                id: summary.id,
                chatIDs: summary.chatIDs,
                title: summary.title,
                kind: summary.kind,
                participantIdentifiers: summary.participantIdentifiers,
                lineageIdentifiers: summary.lineageIdentifiers,
                messageCount: overviewData.aggregate.messageCount,
                sentCount: overviewData.aggregate.sentCount,
                receivedCount: overviewData.aggregate.receivedCount,
                lastMessageDate: overviewData.aggregate.lastMessageDate
            )
            var leaderboard: [ParticipantLeaderboardEntry] = []
            var overviewParticipants: [ParticipantLeaderboardEntry] = []
            var reactionDynamics: [ReactionDynamicsEdge] = []
            var currentUserName = "You"
            do {
                leaderboard = try await contactResolver.resolveLeaderboard(data.participantStats)
                overviewParticipants = try await contactResolver.resolveLeaderboard(
                    overviewData.participantStats
                )
                reactionDynamics = try await contactResolver.resolveReactionDynamics(
                    overviewData.reactionEdges
                )
                currentUserName = try await contactResolver.currentUserDisplayName()
            } catch {
                leaderboard = data.participantStats.map {
                    ParticipantLeaderboardEntry(
                        id: $0.isCurrentUser ? "current-user" : $0.handle,
                        displayName: $0.isCurrentUser ? "You" : $0.handle,
                        isCurrentUser: $0.isCurrentUser,
                        rawHandles: [$0.handle],
                        messageCount: $0.messageCount,
                        reactionMessageCount: $0.reactionMessageCount,
                        reactionsByType: $0.reactionsByType,
                        reactionsGivenByType: $0.reactionsGivenByType
                    )
                }
                overviewParticipants = overviewData.participantStats.map {
                    ParticipantLeaderboardEntry(
                        id: $0.isCurrentUser ? "current-user" : $0.handle,
                        displayName: $0.isCurrentUser ? "You" : $0.handle,
                        isCurrentUser: $0.isCurrentUser,
                        rawHandles: [$0.handle],
                        messageCount: $0.messageCount,
                        reactionMessageCount: $0.reactionMessageCount,
                        reactionsByType: $0.reactionsByType,
                        reactionsGivenByType: $0.reactionsGivenByType
                    )
                }
                reactionDynamics = overviewData.reactionEdges.map {
                    ReactionDynamicsEdge(
                        giverID: $0.giverHandle,
                        giverName: $0.giverHandle == "ME" ? "You" : $0.giverHandle,
                        receiverID: $0.receiverHandle,
                        receiverName: $0.receiverHandle == "ME" ? "You" : $0.receiverHandle,
                        count: $0.count
                    )
                }
            }

            if senderOptions.isEmpty {
                senderOptions = overviewParticipants
                    .map {
                        SenderFilterOption(
                            id: $0.id,
                            title: $0.isCurrentUser ? "\($0.displayName) (You)" : $0.displayName,
                            handles: $0.rawHandles,
                            isCurrentUser: $0.isCurrentUser
                        )
                    }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
            selectedAnalytics = ConversationAnalytics(
                summary: filteredSummary,
                dailyActivity: overviewData.dailyActivity,
                leaderboard: leaderboard,
                reactionDynamics: reactionDynamics,
                currentUserName: currentUserName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
