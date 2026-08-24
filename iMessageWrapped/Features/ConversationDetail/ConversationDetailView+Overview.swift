import SwiftUI

// MARK: - Overview

extension ConversationDetailView {
    var header: some View {
        HStack(spacing: 18) {
            Image(systemName: analytics.summary.kind == .group ? "person.3.fill" : "person.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 5) {
                Text(analytics.summary.title)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                Text(analytics.summary.kind == .group ? "Group conversation" : "Direct conversation")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var lifetimeMetrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 16)],
            spacing: 16
        ) {
            DetailMetric(
                title: "Total messages",
                value: analytics.summary.messageCount.formatted(),
                subtitle: "All-time conversation",
                color: AppTheme.purple
            )
            DetailMetric(
                title: "Monthly average",
                value: monthlyAverage.formatted(.number.precision(.fractionLength(1))),
                subtitle: "Messages per month",
                color: AppTheme.pink
            )
            DetailMetric(
                title: "Daily average",
                value: dailyAverage.formatted(.number.precision(.fractionLength(1))),
                subtitle: "Messages per calendar day",
                color: AppTheme.cyan
            )
            DetailMetric(
                title: "Your messages",
                value: analytics.summary.sentCount.formatted(),
                subtitle: "Sent by you",
                color: AppTheme.orange
            )
            DetailMetric(
                title: "From others",
                value: analytics.summary.receivedCount.formatted(),
                subtitle: "Messages you received",
                color: AppTheme.mint
            )
            DetailMetric(
                title: "Active days",
                value: analytics.dailyActivity.count.formatted(),
                subtitle: "Days with conversation",
                color: AppTheme.purple
            )
            DetailMetric(
                title: "Chat lifetime",
                value: chatLifetimeText,
                subtitle: chatLifetimeDateRange,
                color: AppTheme.cyan
            )
        }
    }

    private var calendarDayCount: Int {
        guard let first = analytics.dailyActivity.first?.date,
              let last = analytics.dailyActivity.last?.date else {
            return 1
        }
        return max(
            1,
            (Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        )
    }

    private var dailyAverage: Double {
        Double(analytics.summary.messageCount) / Double(calendarDayCount)
    }

    private var monthlyAverage: Double {
        Double(analytics.summary.messageCount) / max(1, Double(calendarDayCount) / 30.4375)
    }

    private var chatLifetimeText: String {
        guard let first = analytics.dailyActivity.first?.date,
              let last = analytics.dailyActivity.last?.date else {
            return "—"
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: first,
            to: last
        )
        let years = components.year ?? 0
        let months = components.month ?? 0
        let days = components.day ?? 0
        if years > 0 {
            return months > 0 ? "\(years)y \(months)m" : "\(years)y"
        }
        if months > 0 {
            return days > 0 ? "\(months)m \(days)d" : "\(months)m"
        }
        let inclusiveDays = days + 1
        return inclusiveDays == 1 ? "1 day" : "\(inclusiveDays)d"
    }

    private var chatLifetimeDateRange: String {
        guard let first = analytics.dailyActivity.first?.date,
              let last = analytics.dailyActivity.last?.date else {
            return "No message history"
        }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    @ViewBuilder
    var participants: some View {
        if !analytics.summary.participantIdentifiers.isEmpty {
            ColorfulCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("The crew")
                        .font(.title2.bold())
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(analytics.summary.participantIdentifiers, id: \.self) { participant in
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.fill")
                                Text(participant)
                                if participant == analytics.currentUserName {
                                    Text("YOU")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.pink, in: Capsule())
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                participant == analytics.currentUserName
                                    ? AppTheme.pink
                                    : AppTheme.purple
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                participant == analytics.currentUserName
                                    ? AppTheme.pink.opacity(0.14)
                                    : AppTheme.purple.opacity(0.12),
                                in: Capsule()
                            )
                        }
                    }
                }

            }
        }
    }

    var systemEventsButton: some View {
        Button {
            updateFilters { $0.includeSystemEvents.toggle() }
        } label: {
            HStack {
                Image(systemName: appModel.draftConversationFilters.includeSystemEvents
                    ? "checkmark.circle.fill"
                    : "circle")
                Text("System events")
                Spacer()
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(
                appModel.draftConversationFilters.includeSystemEvents ? .white : AppTheme.purple
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                appModel.draftConversationFilters.includeSystemEvents
                    ? AnyShapeStyle(AppTheme.heroGradient)
                    : AnyShapeStyle(AppTheme.purple.opacity(0.09)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    var usesMessages: Bool {
        leaderboardMetric == .messagesSent || leaderboardMetric == .messagesAndReactions
    }

    var usesReactions: Bool {
        leaderboardMetric != .messagesSent
    }

    func metricIcon(_ metric: LeaderboardMetric) -> String {
        switch metric {
        case .messagesSent: "message.fill"
        case .reactionsReceived: "heart.fill"
        case .reactionsGiven: "hand.thumbsup.fill"
        case .messagesAndReactions: "sparkles"
        case .reactionsPerMessage: "percent"
        }
    }

    func filterMenu<Value>(
        icon: String,
        title: String,
        values: [Value],
        selected: Value,
        label: KeyPath<Value, String>,
        onSelect: @escaping (Value) -> Void
    ) -> some View where Value: Hashable, Value: Identifiable {
        Menu {
            ForEach(values) { value in
                Button {
                    onSelect(value)
                } label: {
                    if value == selected {
                        Label(value[keyPath: label], systemImage: "checkmark")
                    } else {
                        Text(value[keyPath: label])
                    }
                }
            }
        } label: {
            FilterPillLabel(icon: icon, title: title)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    func updateFilters(_ update: (inout ConversationFilters) -> Void) {
        var filters = appModel.draftConversationFilters
        update(&filters)
        appModel.scheduleConversationAnalysis(filters)
    }
}


private struct DetailMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .black))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.2), lineWidth: 1)
        }
        .help("\(title): \(value). \(subtitle).")
    }
}
