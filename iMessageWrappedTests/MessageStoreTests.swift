import Foundation
import Testing
@testable import iMessageWrapped

typealias Handle = MessagesFixture.Handle
typealias Chat = MessagesFixture.Chat

// MARK: - Conversations list

@MainActor
@Suite struct LoadConversationsTests {
    @Test func listsEveryChatOrderedByMessageCount() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let conversations = try await store.loadConversations(since: nil)

        #expect(conversations.map(\.chatIDs) == [[Chat.weekendCrew], [Chat.alex], [Chat.emptyJordan]])
    }

    @Test func countsRawRowsIncludingReactionsAndSystemEvents() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let conversations = try await store.loadConversations(since: nil)
        let alex = try #require(conversations.first { $0.chatIDs == [Chat.alex] })
        let group = try #require(conversations.first { $0.chatIDs == [Chat.weekendCrew] })

        #expect(alex.messageCount == 5)
        #expect(alex.sentCount == 2)
        #expect(alex.receivedCount == 3)
        #expect(group.messageCount == 6)
        #expect(group.sentCount == 2)
        #expect(group.receivedCount == 4)
    }

    @Test func classifiesDirectAndGroupChats() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let conversations = try await store.loadConversations(since: nil)
        let alex = try #require(conversations.first { $0.chatIDs == [Chat.alex] })
        let group = try #require(conversations.first { $0.chatIDs == [Chat.weekendCrew] })

        #expect(alex.kind == .direct)
        #expect(alex.title == Handle.alex)
        #expect(alex.participantIdentifiers == [Handle.alex])
        #expect(group.kind == .group)
        #expect(group.title == "Weekend Crew")
        #expect(Set(group.participantIdentifiers) == [Handle.sam, Handle.jordan])
        #expect(group.lineageIdentifiers == ["iMessage;+;chat123", "GROUP-1", "chat123"])
    }

    @Test func dateCutoffZeroesOlderChatsButKeepsThem() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let conversations = try await store.loadConversations(since: MessagesFixture.day3)
        let alex = try #require(conversations.first { $0.chatIDs == [Chat.alex] })
        let group = try #require(conversations.first { $0.chatIDs == [Chat.weekendCrew] })

        #expect(alex.messageCount == 0)
        #expect(alex.lastMessageDate == nil)
        #expect(group.messageCount == 6)
    }

    @Test func worksWithoutGroupLineageColumns() async throws {
        let fixture = try MessagesFixture(includeLineageColumns: false)
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let conversations = try await store.loadConversations(since: nil)
        let group = try #require(conversations.first { $0.chatIDs == [Chat.weekendCrew] })

        #expect(conversations.count == 3)
        #expect(group.lineageIdentifiers == ["iMessage;+;chat123", "chat123"])
    }
}

// MARK: - Aggregates and daily activity

@MainActor
@Suite struct AggregateQueryTests {
    @Test func defaultFiltersExcludeReactionsAndSystemEvents() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let aggregate = try await store.loadAggregate(
            chatIDs: [Chat.alex],
            since: nil,
            filters: ConversationFilters()
        )

        #expect(aggregate.messageCount == 3)
        #expect(aggregate.sentCount == 2)
        #expect(aggregate.receivedCount == 1)
        #expect(aggregate.lastMessageDate == MessagesFixture.day2.at(9, 0))
    }

    @Test(arguments: [
        (MessageContentFilter.text, MessageDirectionFilter.all, 2),
        (.attachments, .all, 1),
        (.all, .sent, 2),
        (.all, .received, 1),
        (.text, .sent, 1),
    ])
    func contentAndDirectionFilters(
        content: MessageContentFilter,
        direction: MessageDirectionFilter,
        expected: Int
    ) async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        var filters = ConversationFilters()
        filters.content = content
        filters.direction = direction
        let aggregate = try await store.loadAggregate(chatIDs: [Chat.alex], since: nil, filters: filters)

        #expect(aggregate.messageCount == expected)
    }

    @Test func includingSystemEventsCountsEveryRow() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        var filters = ConversationFilters()
        filters.includeSystemEvents = true
        let aggregate = try await store.loadAggregate(chatIDs: [Chat.alex], since: nil, filters: filters)

        #expect(aggregate.messageCount == 5)
    }

    @Test func senderFilterSelectsHandlesAndCurrentUser() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        var filters = ConversationFilters()
        filters.senderHandles = [Handle.sam]
        let samOnly = try await store.loadAggregate(chatIDs: [Chat.weekendCrew], since: nil, filters: filters)
        filters.senderHandles = ["ME", Handle.jordan]
        let meAndJordan = try await store.loadAggregate(chatIDs: [Chat.weekendCrew], since: nil, filters: filters)

        #expect(samOnly.messageCount == 1)
        #expect(meAndJordan.messageCount == 2)
    }

    @Test func senderHandleWithQuoteIsEscaped() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        var filters = ConversationFilters()
        filters.senderHandles = ["o'brien@example.com"]
        let aggregate = try await store.loadAggregate(chatIDs: [Chat.alex], since: nil, filters: filters)

        #expect(aggregate.messageCount == 0)
    }

    @Test func emptyChatListShortCircuits() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let aggregate = try await store.loadAggregate(chatIDs: [], since: nil)
        let daily = try await store.loadDailyActivity(chatIDs: [], since: nil)

        #expect(aggregate.messageCount == 0)
        #expect(daily.isEmpty)
    }

    @Test func dailyActivityBucketsByLocalDay() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let daily = try await store.loadDailyActivity(
            chatIDs: [Chat.alex],
            since: nil,
            filters: ConversationFilters()
        )

        #expect(daily.map(\.date) == [MessagesFixture.day1, MessagesFixture.day2])
        #expect(daily.map(\.sent) == [1, 1])
        #expect(daily.map(\.received) == [1, 0])
    }
}

// MARK: - Filtered conversation data (leaderboard / dynamics)

@MainActor
@Suite struct FilteredConversationDataTests {
    @Test func reactionsCountTowardTotalsAndParticipants() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let data = try await store.loadFilteredConversationData(
            chatIDs: [Chat.alex],
            filters: ConversationFilters()
        )
        let me = try #require(data.participantStats.first { $0.isCurrentUser })
        let alex = try #require(data.participantStats.first { $0.handle == Handle.alex })

        // 3 messages + Alex's ❤️ on my message (counts as received).
        #expect(data.aggregate.messageCount == 4)
        #expect(data.aggregate.sentCount == 2)
        #expect(data.aggregate.receivedCount == 2)
        #expect(me.messageCount == 2)
        #expect(me.reactionsByType == [.loved: 1])
        #expect(alex.messageCount == 1)
        #expect(alex.reactionsGivenByType == [.loved: 1])
        #expect(data.reactionEdges.count == 1)
        #expect(data.reactionEdges.first?.giverHandle == Handle.alex)
        #expect(data.reactionEdges.first?.receiverHandle == "ME")
    }

    @Test func removedReactionsCancelOut() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let data = try await store.loadFilteredConversationData(
            chatIDs: [Chat.weekendCrew],
            filters: ConversationFilters()
        )
        let sam = try #require(data.participantStats.first { $0.handle == Handle.sam })
        let jordan = try #require(data.participantStats.first { $0.handle == Handle.jordan })

        // Jordan's 😂 on Sam was removed; only my 👍 on Jordan survives.
        #expect(data.aggregate.messageCount == 4)
        #expect(sam.reactionsByType.isEmpty)
        #expect(jordan.reactionsByType == [.liked: 1])
        #expect(data.reactionEdges.count == 1)
        #expect(data.reactionEdges.first?.giverHandle == "ME")
        #expect(data.reactionEdges.first?.receiverHandle == Handle.jordan)
    }

    @Test(arguments: [
        (ActivityScope.messages, 3),
        (.reactions, 1),
        (.both, 4),
    ])
    func scopeSelectsMessagesReactionsOrBoth(scope: ActivityScope, expected: Int) async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        var filters = ConversationFilters()
        filters.scope = scope
        let data = try await store.loadFilteredConversationData(chatIDs: [Chat.weekendCrew], filters: filters)

        #expect(data.aggregate.messageCount == expected)
    }

    @Test func reactionTypeFilter() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        var filters = ConversationFilters()
        filters.scope = .reactions
        filters.reactionType = .laughed
        let laughed = try await store.loadFilteredConversationData(chatIDs: [Chat.alex], filters: filters)
        filters.reactionType = .loved
        let loved = try await store.loadFilteredConversationData(chatIDs: [Chat.alex], filters: filters)

        #expect(laughed.aggregate.messageCount == 0)
        #expect(loved.aggregate.messageCount == 1)
    }
}

// MARK: - Movers

@MainActor
@Suite struct MoverStatsTests {
    private func moverStats(
        _ store: MessageStore,
        responseFilter: MoverResponseFilter
    ) async throws -> [String: RawMoverStats] {
        let stats = try await store.loadMoverStats(
            chatIDs: [Chat.weekendCrew],
            responseWindow: 5 * 60,
            responseFilter: responseFilter,
            responderContext: .all,
            lookbackWindow: 60 * 60,
            since: nil
        )
        return Dictionary(uniqueKeysWithValues: stats.map { ($0.handle, $0) })
    }

    @Test func messageRepliesWithinWindowCountAsResponders() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let stats = try await moverStats(store, responseFilter: .messages)

        #expect(stats[Handle.sam]?.totalResponders == 2)
        #expect(stats[Handle.sam]?.totalFollowUpMessages == 2)
        #expect(stats[Handle.jordan]?.totalResponders == 1)
        #expect(stats["ME"]?.totalResponders == 0)
        #expect(stats["ME"]?.isCurrentUser == true)
    }

    @Test func reactionRepliesIgnoreRemovedReactions() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let stats = try await moverStats(store, responseFilter: .reactions)

        #expect(stats[Handle.sam]?.totalResponders == 0)
        #expect(stats[Handle.jordan]?.totalResponders == 1)
    }

    @Test func invalidWindowsReturnNothing() async throws {
        let fixture = try MessagesFixture()
        defer { fixture.remove() }
        let store = MessageStore(databaseURL: fixture.url)

        let stats = try await store.loadMoverStats(
            chatIDs: [Chat.weekendCrew],
            responseWindow: 0,
            responseFilter: .both,
            responderContext: .all,
            lookbackWindow: 60,
            since: nil
        )

        #expect(stats.isEmpty)
    }
}

// MARK: - Database plumbing

@MainActor
@Suite struct DatabaseTests {
    @Test func missingDatabaseThrowsUnavailable() async throws {
        let store = MessageStore(
            databaseURL: FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID()).db")
        )

        await #expect {
            _ = try await store.loadConversations(since: nil)
        } throws: { error in
            guard case MessageStoreError.databaseUnavailable = error else { return false }
            return true
        }
    }

    @Test func appleDateHandlesSecondsAndNanoseconds() async throws {
        let store = MessageStore(databaseURL: URL(filePath: "/dev/null"))
        let date = MessagesFixture.day1.at(10, 0)
        let seconds = Int64(date.timeIntervalSinceReferenceDate)

        #expect(await store.appleDate(from: 0) == nil)
        #expect(await store.appleDate(from: seconds) == date)
        #expect(await store.appleDate(from: MessagesFixture.appleNanoseconds(date)) == date)
    }
}

// MARK: - Time ranges

@MainActor
@Suite struct AnalyticsRangeTests {
    @Test func pickerOrderRunsShortestToLongest() {
        #expect(AnalyticsRange.allCases == [
            .sevenDays, .thirtyDays, .sixMonths, .oneYear, .yearToDate, .allTime,
        ])
    }

    @Test func sevenDaysStartsOneWeekAgo() throws {
        let start = try #require(AnalyticsRange.sevenDays.startDate)
        let expected = try #require(Calendar.current.date(byAdding: .day, value: -7, to: .now))

        #expect(abs(start.timeIntervalSince(expected)) < 5)
    }

    @Test func yearToDateStartsJanuaryFirstOfThisYear() throws {
        let start = try #require(AnalyticsRange.yearToDate.startDate)
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: .now)

        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            == DateComponents(year: thisYear, month: 1, day: 1, hour: 0, minute: 0))
        #expect(AnalyticsRange.yearToDate.title == String(thisYear))
        #expect(AnalyticsRange.yearToDate.periodDescription == "\(thisYear) so far")
    }

    @Test func allTimeHasNoStartDate() {
        #expect(AnalyticsRange.allTime.startDate == nil)
    }
}
