import SwiftUI

// MARK: - Movers

extension ConversationDetailView {
    var moverWorkspace: some View {
        HStack(alignment: .top, spacing: 20) {
            moverFilters
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 410)

            moverAnalysis
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var moverFilters: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mover filters")
                        .font(.title3.bold())
                    Text("Choose when and how responses count")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Time period", systemImage: "calendar")
                        .font(.headline)
                        .foregroundStyle(AppTheme.purple)
                        .help("Limits which trigger messages are included in the averages.")

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 125), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(AnalyticsRange.allCases) { range in
                            moverFilterButton(
                                title: range.title,
                                icon: nil,
                                isSelected: moverRange == range
                            ) {
                                moverRange = range
                                refreshMovers()
                            }
                            .help(
                                "Use trigger messages sent during the last \(range.title.lowercased())."
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Rank by", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                        .foregroundStyle(AppTheme.orange)
                        .help("Chooses which average determines leaderboard order and bar length.")

                    ForEach(MoverSortMetric.allCases) { metric in
                        moverFilterButton(
                            title: metric.title,
                            icon: metric.systemImage,
                            isSelected: moverSortMetric == metric
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                moverSortMetric = metric
                            }
                        }
                        .help(metric.helpText)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Count responses as", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.pink)
                        .help("Chooses which activity makes someone count as a responder.")

                    ForEach(MoverResponseFilter.allCases) { filter in
                        moverFilterButton(
                            title: filter.title,
                            icon: filter.systemImage,
                            isSelected: moverResponseFilter == filter
                        ) {
                            moverResponseFilter = filter
                            refreshMovers()
                        }
                        .help(filter.helpText)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Response window", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(AppTheme.orange)
                        .help("How long after each trigger message responses can count.")

                    Menu {
                        ForEach(moverWindowOptions, id: \.self) { seconds in
                            Button {
                                moverWindowSeconds = seconds
                                refreshMovers()
                            } label: {
                                if moverWindowSeconds == seconds {
                                    Label(responseWindowTitle(seconds), systemImage: "checkmark")
                                } else {
                                    Text(responseWindowTitle(seconds))
                                }
                            }
                        }
                    } label: {
                        BrandedMenuLabel(
                            icon: "timer",
                            title: responseWindowTitle(moverWindowSeconds),
                            colors: [AppTheme.orange, AppTheme.pink]
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(
                        "Count responses arriving within \(responseWindowTitle(moverWindowSeconds).lowercased()) after each trigger message."
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Responder context", systemImage: "person.2.badge.gearshape")
                        .font(.headline)
                        .foregroundStyle(AppTheme.cyan)
                        .help("Separates newly activated people from people already in the conversation.")

                    ForEach(MoverResponderContext.allCases) { context in
                        moverFilterButton(
                            title: context.title,
                            icon: context.systemImage,
                            isSelected: moverResponderContext == context
                        ) {
                            moverResponderContext = context
                            refreshMovers()
                        }
                        .help(context.helpText)
                    }

                    if moverResponderContext != .all {
                        Menu {
                            ForEach(moverLookbackOptions, id: \.self) { minutes in
                                Button {
                                    moverLookbackMinutes = minutes
                                    refreshMovers()
                                } label: {
                                    if moverLookbackMinutes == minutes {
                                        Label(
                                            "Look back \(lookbackWindowTitle(minutes))",
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text("Look back \(lookbackWindowTitle(minutes))")
                                    }
                                }
                            }
                        } label: {
                            BrandedMenuLabel(
                                icon: "clock.arrow.circlepath",
                                title: "Look back \(lookbackWindowTitle(moverLookbackMinutes))",
                                colors: [AppTheme.cyan, AppTheme.purple]
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(
                            "Checks whether each responder messaged during the \(lookbackWindowTitle(moverLookbackMinutes).lowercased()) before the trigger."
                        )
                    }
                }
            }
        }
    }

    private var moverAnalysis: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Who gets the chat moving?")
                        .font(.title2.bold())
                    Text(
                        "Compare distinct responders and the average number of follow-up messages."
                    )
                    .foregroundStyle(.secondary)
                }

                Label(
                    moverDescription,
                    systemImage: "person.2.wave.2.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.purple)

                if moverResponderContext != .all {
                    Label(
                        moverContextDescription,
                        systemImage: moverResponderContext.systemImage
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                if rankedMoverEntries.isEmpty, !appModel.isMoversLoading {
                    ContentUnavailableView(
                        "No mover activity",
                        systemImage: "bolt.slash",
                        description: Text("There are no normal messages to compare in this group.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(rankedMoverEntries.enumerated()), id: \.element.id) {
                            index,
                            entry in
                            MoverRow(
                                rank: index + 1,
                                entry: entry,
                                maximumValue: maximumMoverValue,
                                sortMetric: moverSortMetric
                            )
                        }
                    }
                }
            }
        }
        .overlay {
            if appModel.isMoversLoading {
                SectionLoadingOverlay(title: "Finding the biggest mover")
            }
        }
    }

    private var rankedMoverEntries: [MoverLeaderboardEntry] {
        appModel.moverEntries.sorted { left, right in
            let leftValue = moverSortValue(for: left)
            let rightValue = moverSortValue(for: right)
            if leftValue == rightValue {
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    == .orderedAscending
            }
            return leftValue > rightValue
        }
    }

    private var maximumMoverValue: Double {
        rankedMoverEntries.map(moverSortValue).max() ?? 1
    }

    private func moverSortValue(for entry: MoverLeaderboardEntry) -> Double {
        switch moverSortMetric {
        case .peoplePerMessage:
            return entry.averageResponders
        case .followUpsPerMessage:
            return entry.averageFollowUpMessages
        }
    }

    private var moverDescription: String {
        let window = responseWindowTitle(moverWindowSeconds).lowercased()
        switch moverResponseFilter {
        case .messages:
            return "Counts unique people who message within \(window) of each message"
        case .reactions:
            return "Counts unique people who react to that message within \(window)"
        case .both:
            return "Counts unique people who message or react within \(window)"
        }
    }

    private var moverContextDescription: String {
        let lookback = lookbackWindowTitle(moverLookbackMinutes).lowercased()
        switch moverResponderContext {
        case .all:
            return "Includes every responder"
        case .newlyActivated:
            return "Only people who had not messaged during the previous \(lookback)"
        case .alreadyActive:
            return "Only people who had messaged during the previous \(lookback)"
        }
    }

    func refreshMovers() {
        appModel.scheduleMoversAnalysis(
            responseWindowSeconds: moverWindowSeconds,
            responseFilter: moverResponseFilter,
            responderContext: moverResponderContext,
            lookbackWindowMinutes: moverLookbackMinutes,
            range: moverRange
        )
    }

    private func moverFilterButton(
        title: String,
        icon: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                Spacer()
            }
            .font(.subheadline.bold())
            .foregroundStyle(isSelected ? .white : AppTheme.purple)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(AppTheme.heroGradient)
                } else {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(AppTheme.purple.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func responseWindowTitle(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) sec"
        }
        return lookbackWindowTitle(seconds / 60)
    }

    private func lookbackWindowTitle(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

}

private struct MoverRow: View {
    let rank: Int
    let entry: MoverLeaderboardEntry
    let maximumValue: Double
    let sortMetric: MoverSortMetric

    private var sortValue: Double {
        switch sortMetric {
        case .peoplePerMessage:
            return entry.averageResponders
        case .followUpsPerMessage:
            return entry.averageFollowUpMessages
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(rank <= 3 ? AppTheme.orange : .secondary)
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
                        .fill(AppTheme.orange.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    entry.isCurrentUser
                                        ? AppTheme.heroGradient
                                        : AppTheme.coolGradient
                                )
                                .frame(
                                    width: geometry.size.width
                                        * max(
                                            0.02,
                                            sortValue / max(maximumValue, 0.0001)
                                        )
                                )
                        }
                }
                .frame(height: 7)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    entry.averageResponders.formatted(
                        .number.precision(.fractionLength(2))
                    )
                )
                .font(.system(.headline, design: .rounded, weight: .bold))
                .help(
                    "Average distinct responders per trigger message: \(entry.totalResponders.formatted()) responder appearances across \(entry.messageCount.formatted()) messages."
                )
                Text("people / msg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Distinct other people who responded, averaged across this person's messages.")
                Text(
                    "\(entry.averageFollowUpMessages.formatted(.number.precision(.fractionLength(2)))) follow-ups / msg"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.orange)
                    .help(
                        "Average follow-up messages per trigger: \(entry.totalFollowUpMessages.formatted()) follow-up messages across \(entry.messageCount.formatted()) messages. Multiple messages from one responder each count."
                    )
                Text("based on \(entry.messageCount.formatted()) messages")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("The number of this person's non-reaction messages used as the sample.")
            }
            .frame(width: 135, alignment: .trailing)
        }
        .padding(12)
        .background(
            entry.isCurrentUser ? AppTheme.pink.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}
