import SwiftUI

// MARK: - Leaderboard

extension ConversationDetailView {
    var leaderboardWorkspace: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 16) {
                timeSelector
                filterLens
            }
            .frame(minWidth: 330, idealWidth: 410, maxWidth: 460)

            leaderboard
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var timeSelector: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Time period")
                        .font(.headline)
                    Spacer()
                    Text("Choose one")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Button {
                            updateFilters { $0.range = range }
                        } label: {
                            Text(range.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(
                                    appModel.draftConversationFilters.range == range
                                        ? .white
                                        : AppTheme.purple
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background {
                                    if appModel.draftConversationFilters.range == range {
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(AppTheme.heroGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(AppTheme.purple.opacity(0.08))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(
                            "Limits leaderboard activity to \(range.periodDescription)."
                        )
                    }
                }
            }
        }
    }

    var pageSelector: some View {
        HStack(spacing: 8) {
            ForEach(availablePages, id: \.self) { destination in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        page = destination
                    }
                    if destination == .movers {
                        refreshMovers()
                    } else if destination == .messages {
                        refreshMessageHighlights()
                    }
                } label: {
                    Label(destination.rawValue, systemImage: destination.icon)
                        .font(.headline)
                        .foregroundStyle(page == destination ? .white : AppTheme.purple)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background {
                            if page == destination {
                                Capsule().fill(AppTheme.heroGradient)
                            } else {
                                Capsule().fill(AppTheme.purple.opacity(0.09))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var availablePages: [Page] {
        Page.allCases.filter { analytics.summary.kind == .group || $0 != .movers }
    }

    private var filterLens: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rank by")
                            .font(.title3.bold())
                        Text("Pick a leaderboard, then refine its data")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(LeaderboardMetric.allCases) { metric in
                        Button {
                            leaderboardMetric = metric
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: metricIcon(metric))
                                    .font(.title2.bold())
                                Text(metric.title)
                                    .font(.subheadline.bold())
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                                .foregroundStyle(
                                    leaderboardMetric == metric
                                        ? .white
                                        : AppTheme.purple
                                )
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 68)
                                .padding(.vertical, 15)
                                .background {
                                    if leaderboardMetric == metric {
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(AppTheme.heroGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(AppTheme.purple.opacity(0.08))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(metric.helpText)
                    }
                }

                if usesMessages {
                    messageFilters
                }

                if usesReactions {
                    reactionFilters
                }

                Label(
                    "Results update automatically",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var messageFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Message filters", systemImage: "message.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.purple)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                filterMenu(
                    icon: "text.bubble.fill",
                    title: appModel.draftConversationFilters.content.title,
                    values: MessageContentFilter.allCases,
                    selected: appModel.draftConversationFilters.content,
                    label: \.title
                ) { content in
                    updateFilters { $0.content = content }
                }

                systemEventsButton
            }
        }
        .padding(16)
        .background(AppTheme.purple.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }

    private var reactionFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reaction filters", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.pink)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                filterMenu(
                    icon: "heart.fill",
                    title: "\(appModel.draftConversationFilters.reactionType.symbol) \(appModel.draftConversationFilters.reactionType.title)",
                    values: ReactionType.allCases,
                    selected: appModel.draftConversationFilters.reactionType,
                    label: \.title
                ) { reaction in
                    updateFilters { $0.reactionType = reaction }
                }

            }
        }
        .padding(16)
        .background(AppTheme.pink.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }

    private var leaderboard: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Group leaderboard")
                            .font(.title2.bold())
                        Text("See how everyone stacks up")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label(leaderboardMetric.title, systemImage: metricIcon(leaderboardMetric))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppTheme.coolGradient, in: Capsule())
                }

                if rankedEntries.isEmpty {
                    Text("No participant activity in this date range.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(rankedEntries.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(
                                rank: index + 1,
                                entry: entry,
                                metric: leaderboardMetric,
                                reactionType: appModel.conversationFilters.reactionType,
                                maximumValue: maximumLeaderboardValue
                            )
                        }
                    }
                }
            }
        }
        .overlay {
            if appModel.isLeaderboardLoading {
                SectionLoadingOverlay(title: "Updating leaderboard")
            }
        }
    }

    private var rankedEntries: [ParticipantLeaderboardEntry] {
        analytics.leaderboard.sorted { left, right in
            let leftValue = leaderboardValue(for: left)
            let rightValue = leaderboardValue(for: right)
            if leftValue == rightValue {
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
            return leftValue > rightValue
        }
    }

    private var maximumLeaderboardValue: Double {
        rankedEntries.map(leaderboardValue).max() ?? 1
    }

    private func leaderboardValue(for entry: ParticipantLeaderboardEntry) -> Double {
        switch leaderboardMetric {
        case .messagesSent:
            return Double(entry.messageCount)
        case .reactionsReceived:
            return Double(
                entry.reactionCount(for: appModel.conversationFilters.reactionType)
            )
        case .reactionsGiven:
            return Double(
                entry.reactionsGiven(for: appModel.conversationFilters.reactionType)
            )
        case .messagesAndReactions:
            return Double(
                entry.messageCount
                    + entry.reactionCount(for: appModel.conversationFilters.reactionType)
            )
        case .reactionsPerMessage:
            return entry.reactionRate(for: appModel.conversationFilters.reactionType)
        }
    }

}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: ParticipantLeaderboardEntry
    let metric: LeaderboardMetric
    let reactionType: ReactionType
    let maximumValue: Double

    private var value: Double {
        switch metric {
        case .messagesSent:
            return Double(entry.messageCount)
        case .reactionsReceived:
            return Double(entry.reactionCount(for: reactionType))
        case .reactionsGiven:
            return Double(entry.reactionsGiven(for: reactionType))
        case .messagesAndReactions:
            return Double(entry.messageCount + entry.reactionCount(for: reactionType))
        case .reactionsPerMessage:
            return entry.reactionRate(for: reactionType)
        }
    }

    private var valueText: String {
        switch metric {
        case .messagesSent:
            return entry.messageCount.formatted()
        case .reactionsReceived:
            return entry.reactionCount(for: reactionType).formatted()
        case .reactionsGiven:
            return entry.reactionsGiven(for: reactionType).formatted()
        case .messagesAndReactions:
            return Int(value).formatted()
        case .reactionsPerMessage:
            return value.formatted(.number.precision(.fractionLength(2)))
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(rank <= 3 ? AppTheme.pink : .secondary)
                .frame(width: 34)

            ZStack {
                Circle()
                    .fill(entry.isCurrentUser ? AppTheme.heroGradient : AppTheme.coolGradient)
                Text(entry.displayName.prefix(1).uppercased())
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(entry.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if entry.isCurrentUser {
                        Text("YOU")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.pink, in: Capsule())
                    }
                }

                GeometryReader { geometry in
                    Capsule()
                        .fill(AppTheme.purple.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(entry.isCurrentUser ? AppTheme.heroGradient : AppTheme.coolGradient)
                                .frame(
                                    width: geometry.size.width
                                        * max(0.02, value / max(maximumValue, 0.0001))
                                )
                        }
                }
                .frame(height: 7)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(valueText)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(valueCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(12)
        .background(
            entry.isCurrentUser ? AppTheme.pink.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .help("\(metric.helpText) This participant's value is \(valueText).")
    }

    private var valueCaption: String {
        switch metric {
        case .messagesSent: "messages"
        case .reactionsReceived: "reactions"
        case .reactionsGiven: "given"
        case .messagesAndReactions: "combined"
        case .reactionsPerMessage: "reacts / msg"
        }
    }
}
