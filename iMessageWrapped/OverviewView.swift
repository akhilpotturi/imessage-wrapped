import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            PlayfulBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    metrics

                    if !appModel.directChats.isEmpty {
                        FriendsPodium(conversations: Array(appModel.directChats.prefix(3)))
                    }

                    RankedConversationChart(
                        title: "Your inner circle",
                        subtitle: "The people lighting up your Messages",
                        conversations: Array(appModel.directChats.prefix(10)),
                        colors: [AppTheme.pink, AppTheme.purple]
                    )

                    RankedConversationChart(
                        title: "Group chat legends",
                        subtitle: "Where the conversation never stops",
                        conversations: Array(appModel.groupChats.prefix(10)),
                        colors: [AppTheme.orange, AppTheme.pink]
                    )
                }
                .padding(32)
            }
        }
        .navigationTitle("Overview")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR MESSAGE UNIVERSE")
                .font(.caption.bold())
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.82))

            Text("Look who keeps\nyou talking.")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("A colorful look at all of your conversations.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 28))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "message.fill")
                .font(.system(size: 110))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-12))
                .padding(24)
        }
        .shadow(color: AppTheme.pink.opacity(0.24), radius: 28, y: 14)
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: 16)],
            spacing: 16
        ) {
            MetricCard(
                title: "Messages",
                value: appModel.totalMessages.formatted(),
                systemImage: "bubble.left.and.bubble.right.fill",
                colors: [AppTheme.purple, AppTheme.cyan]
            )
            MetricCard(
                title: "People",
                value: appModel.directChats.count.formatted(),
                systemImage: "person.2.fill",
                colors: [AppTheme.pink, AppTheme.orange]
            )
            MetricCard(
                title: "Group chats",
                value: appModel.groupChats.count.formatted(),
                systemImage: "person.3.fill",
                colors: [AppTheme.cyan, AppTheme.mint]
            )
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(colors[0].opacity(0.18), lineWidth: 1)
        }
    }
}

private struct FriendsPodium: View {
    let conversations: [ConversationSummary]
    @State private var isPresented = false

    private var ordered: [(rank: Int, conversation: ConversationSummary)] {
        guard !conversations.isEmpty else { return [] }
        var result: [(Int, ConversationSummary)] = []
        if conversations.count > 1 { result.append((2, conversations[1])) }
        result.append((1, conversations[0]))
        if conversations.count > 2 { result.append((3, conversations[2])) }
        return result
    }

    var body: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The podium")
                        .font(.title2.bold())
                    Text("Your most messaged people")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(ordered, id: \.conversation.id) { item in
                        PodiumPlace(
                            rank: item.rank,
                            conversation: item.conversation,
                            isPresented: isPresented
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .bottom)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.72).delay(0.15)) {
                isPresented = true
            }
        }
    }
}

private struct PodiumPlace: View {
    let rank: Int
    let conversation: ConversationSummary
    let isPresented: Bool

    private var height: CGFloat {
        switch rank {
        case 1: 140
        case 2: 105
        default: 80
        }
    }

    private var gradient: LinearGradient {
        switch rank {
        case 1:
            LinearGradient(colors: [AppTheme.orange, AppTheme.pink], startPoint: .top, endPoint: .bottom)
        case 2:
            LinearGradient(colors: [AppTheme.cyan, AppTheme.purple], startPoint: .top, endPoint: .bottom)
        default:
            LinearGradient(colors: [AppTheme.pink, AppTheme.purple], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: rank == 1 ? 68 : 58, height: rank == 1 ? 68 : 58)
                Text(conversation.title.prefix(1).uppercased())
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .topTrailing) {
                if rank == 1 {
                    Text("👑")
                        .font(.title2)
                        .offset(x: 7, y: -15)
                }
            }

            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)

            Text("\(conversation.messageCount.formatted()) messages")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(gradient)
                Text("#\(rank)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
            }
            .frame(height: isPresented ? height : 8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RankedConversationChart: View {
    let title: String
    let subtitle: String
    let conversations: [ConversationSummary]
    let colors: [Color]

    var body: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                if conversations.isEmpty {
                    Text("No conversations in this date range.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart(conversations) { conversation in
                        BarMark(
                            x: .value("Messages", conversation.messageCount),
                            y: .value("Conversation", conversation.title)
                        )
                        .clipShape(Capsule())
                        .foregroundStyle(
                            LinearGradient(
                                colors: colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .annotation(position: .trailing) {
                            Text(conversation.messageCount.formatted())
                                .font(.caption.bold())
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartLegend(.hidden)
                    .frame(height: CGFloat(max(220, conversations.count * 36)))
                }
            }
        }
    }
}
