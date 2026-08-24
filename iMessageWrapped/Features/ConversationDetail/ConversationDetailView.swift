import SwiftUI

// MARK: - Conversation detail shell

struct ConversationDetailView: View {
    enum Page: String, CaseIterable {
        case overview = "Overview"
        case leaderboard = "Leaderboard"
        case messages = "Messages"
        case dynamics = "Dynamics"
        case movers = "Movers"

        var icon: String {
            switch self {
            case .overview: "sparkles.rectangle.stack.fill"
            case .leaderboard: "trophy.fill"
            case .messages: "quote.bubble.fill"
            case .dynamics: "square.grid.3x3.fill"
            case .movers: "bolt.fill"
            }
        }
    }

    @EnvironmentObject var appModel: AppModel
    let analytics: ConversationAnalytics
    @State var page: Page = .overview
    @State var leaderboardMetric: LeaderboardMetric = .messagesAndReactions
    @State var dynamicsRange: AnalyticsRange = .allTime
    @State var dynamicsReactionType: ReactionType = .all
    @State var moverWindowSeconds = 3_600
    @State var moverResponseFilter: MoverResponseFilter = .both
    @State var moverRange: AnalyticsRange = .allTime
    @State var moverResponderContext: MoverResponderContext = .all
    @State var moverLookbackMinutes = 60
    @State var moverSortMetric: MoverSortMetric = .peoplePerMessage
    @State var messageSampleMetric: MessageSampleMetric = .mostReacted
    @State var messageHighlightsRange: AnalyticsRange = .allTime

    let moverWindowOptions = [30, 60, 120, 300, 900, 1_800, 3_600, 7_200, 21_600]
    let moverLookbackOptions = [15, 30, 60, 120, 360, 720, 1_440]

    var body: some View {
        ZStack {
            PlayfulBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    pageSelector

                    switch page {
                    case .overview:
                        participants
                        lifetimeMetrics
                    case .leaderboard:
                        leaderboardWorkspace
                    case .messages:
                        messageSamplesWorkspace
                    case .dynamics:
                        dynamicsFilters
                        dynamicsHeatMap
                    case .movers:
                        moverWorkspace
                    }
                }
                .padding(32)
            }
        }
        .navigationTitle(analytics.summary.title)
    }

}
