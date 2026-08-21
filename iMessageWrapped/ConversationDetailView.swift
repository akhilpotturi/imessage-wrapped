import Charts
import SwiftUI

struct ConversationDetailView: View {
    private enum Page: String, CaseIterable {
        case overview = "Overview"
        case leaderboard = "Leaderboard"
        case messages = "Messages"
        case dynamics = "Dynamics"

        var icon: String {
            switch self {
            case .overview: "sparkles.rectangle.stack.fill"
            case .leaderboard: "trophy.fill"
            case .messages: "chart.xyaxis.line"
            case .dynamics: "square.grid.3x3.fill"
            }
        }
    }

    @EnvironmentObject private var appModel: AppModel
    let analytics: ConversationAnalytics
    @State private var page: Page = .overview
    @State private var leaderboardMetric: LeaderboardMetric = .messagesAndReactions
    @State private var dynamicsRange: AnalyticsRange = .allTime
    @State private var dynamicsReactionType: ReactionType = .all

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
                        messageActivity
                    case .dynamics:
                        dynamicsFilters
                        dynamicsHeatMap
                    }
                }
                .padding(32)
            }
        }
        .navigationTitle(analytics.summary.title)
    }

    private var dynamicsFilters: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dynamics filters")
                            .font(.title3.bold())
                        Text("Choose the reaction relationships to map")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Menu {
                        ForEach(ReactionType.allCases) { type in
                            Button {
                                dynamicsReactionType = type
                                appModel.scheduleDynamicsAnalysis(
                                    range: dynamicsRange,
                                    reactionType: type
                                )
                            } label: {
                                if dynamicsReactionType == type {
                                    Label("\(type.symbol) \(type.title)", systemImage: "checkmark")
                                } else {
                                    Text("\(type.symbol) \(type.title)")
                                }
                            }
                        }
                    } label: {
                        BrandedMenuLabel(
                            icon: "heart.fill",
                            title: "\(dynamicsReactionType.symbol) \(dynamicsReactionType.title)",
                            colors: [AppTheme.pink, AppTheme.orange]
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack(spacing: 10) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Button {
                            dynamicsRange = range
                            appModel.scheduleDynamicsAnalysis(
                                range: range,
                                reactionType: dynamicsReactionType
                            )
                        } label: {
                            Text(range.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(dynamicsRange == range ? .white : AppTheme.purple)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background {
                                    if dynamicsRange == range {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(AppTheme.heroGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(AppTheme.purple.opacity(0.08))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var messageActivity: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Message activity")
                    .font(.title2.bold())
                Text("All-time daily volume for this conversation")
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(analytics.dailyActivity) { day in
                        LineMark(
                            x: .value("Date", day.date),
                            y: .value("Messages", day.total)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .foregroundStyle(AppTheme.heroGradient)

                        AreaMark(
                            x: .value("Date", day.date),
                            y: .value("Messages", day.total)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.purple.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .frame(height: 340)
            }
        }
    }

    private var dynamicsHeatMap: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reaction dynamics")
                            .font(.title2.bold())
                        Text("Rows gave reactions → columns received them")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Low")
                        ForEach(1...4, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.pink.opacity(Double(level) * 0.23))
                                .frame(width: 18, height: 18)
                        }
                        Text("High")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if dynamicsGivers.isEmpty || dynamicsReceivers.isEmpty {
                    ContentUnavailableView(
                        "No reaction dynamics",
                        systemImage: "heart.slash",
                        description: Text("This conversation has no active Apple reactions.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView(.horizontal) {
                        dynamicsGrid
                            .padding(.top, 8)
                    }
                }
            }
            .overlay {
                if appModel.isDynamicsLoading {
                    SectionLoadingOverlay(title: "Updating dynamics")
                }
            }
        }
    }

    private var dynamicsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                Text("Giver ↓  Receiver →")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 138, alignment: .trailing)

                ForEach(dynamicsReceivers) { receiver in
                    Text(receiver.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .frame(width: 46, alignment: .leading)
                        .rotationEffect(.degrees(-55), anchor: .leading)
                        .frame(width: 46, height: 88, alignment: .bottom)
                }
            }

            ForEach(dynamicsGivers) { giver in
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(giver.name)
                            .lineLimit(1)
                        if giver.id == "current-user" {
                            Text("YOU")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(AppTheme.pink, in: Capsule())
                        }
                    }
                    .font(.caption.bold())
                    .frame(width: 138, alignment: .trailing)

                    ForEach(dynamicsReceivers) { receiver in
                        ReactionHeatCell(
                            count: dynamicsCount(giverID: giver.id, receiverID: receiver.id),
                            maximum: maximumDynamicsCount
                        )
                    }
                }
            }
        }
    }

    private var dynamicsGivers: [DynamicsPerson] {
        uniqueDynamicsPeople(
            analytics.reactionDynamics.map {
                DynamicsPerson(id: $0.giverID, name: $0.giverName)
            }
        )
    }

    private var dynamicsReceivers: [DynamicsPerson] {
        uniqueDynamicsPeople(
            analytics.reactionDynamics.map {
                DynamicsPerson(id: $0.receiverID, name: $0.receiverName)
            }
        )
    }

    private var maximumDynamicsCount: Int {
        analytics.reactionDynamics.map(\.count).max() ?? 1
    }

    private func dynamicsCount(giverID: String, receiverID: String) -> Int {
        analytics.reactionDynamics.first {
            $0.giverID == giverID && $0.receiverID == receiverID
        }?.count ?? 0
    }

    private func uniqueDynamicsPeople(_ people: [DynamicsPerson]) -> [DynamicsPerson] {
        var unique: [String: DynamicsPerson] = [:]
        for person in people {
            unique[person.id] = person
        }
        return unique.values.sorted {
            if $0.id == "current-user" { return true }
            if $1.id == "current-user" { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var leaderboardWorkspace: some View {
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
                    }
                }
            }
        }
    }

    private var pageSelector: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases, id: \.self) { destination in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        page = destination
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

    private var header: some View {
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

    private var lifetimeMetrics: some View {
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

    @ViewBuilder
    private var participants: some View {
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

    private func personMenu(
        icon: String,
        emptyTitle: String,
        selectedHandles: [String],
        onSelect: @escaping ([String]) -> Void
    ) -> some View {
        Menu {
            Button {
                onSelect([])
            } label: {
                if selectedHandles.isEmpty {
                    Label(emptyTitle, systemImage: "checkmark")
                } else {
                    Text(emptyTitle)
                }
            }

            Divider()

            ForEach(appModel.senderOptions) { sender in
                Button {
                    onSelect(sender.handles)
                } label: {
                    if Set(selectedHandles) == Set(sender.handles) {
                        Label(sender.title, systemImage: "checkmark")
                    } else {
                        Text(sender.title)
                    }
                }
            }
        } label: {
            FilterPillLabel(
                icon: icon,
                title: selectedPersonTitle(
                    emptyTitle: emptyTitle,
                    selectedHandles: selectedHandles
                )
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func selectedPersonTitle(
        emptyTitle: String,
        selectedHandles: [String]
    ) -> String {
        guard !selectedHandles.isEmpty else {
            return emptyTitle
        }
        return appModel.senderOptions.first {
            Set($0.handles) == Set(selectedHandles)
        }?.title ?? "Selected sender"
    }

    private var systemEventsButton: some View {
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

    private var usesMessages: Bool {
        leaderboardMetric == .messagesSent || leaderboardMetric == .messagesAndReactions
    }

    private var usesReactions: Bool {
        leaderboardMetric != .messagesSent
    }

    private func metricIcon(_ metric: LeaderboardMetric) -> String {
        switch metric {
        case .messagesSent: "message.fill"
        case .reactionsReceived: "heart.fill"
        case .reactionsGiven: "hand.thumbsup.fill"
        case .messagesAndReactions: "sparkles"
        case .reactionsPerMessage: "percent"
        }
    }

    private var metricTitles: (String, String, String) {
        switch appModel.conversationFilters.scope {
        case .messages:
            ("Messages", "Sent by you", "From others")
        case .reactions:
            ("Reactions", "Given by you", "On your messages")
        case .both:
            ("Total activity", "Your activity", "Incoming activity")
        }
    }

    private func filterMenu<Value>(
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

    private func updateFilters(_ update: (inout ConversationFilters) -> Void) {
        var filters = appModel.draftConversationFilters
        update(&filters)
        appModel.scheduleConversationAnalysis(filters)
    }
}

private struct DynamicsPerson: Identifiable {
    let id: String
    let name: String
}

private struct SectionLoadingOverlay: View {
    let title: String
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.pink.opacity(0.3), lineWidth: 3)
                        .frame(width: 58, height: 58)
                        .scaleEffect(isPulsing ? 1.55 : 0.75)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: isPulsing
                        )

                    Image(systemName: "sparkles")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(AppTheme.heroGradient, in: Circle())
                        .scaleEffect(isPulsing ? 1.05 : 0.95)
                        .animation(
                            .easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }

                Text(title)
                    .font(.headline)
            }
            .padding(24)
        }
        .onAppear {
            isPulsing = true
        }
        .transition(.opacity)
    }
}

private struct ReactionHeatCell: View {
    let count: Int
    let maximum: Int

    private var intensity: Double {
        guard count > 0 else { return 0.035 }
        return 0.18 + (Double(count) / Double(max(maximum, 1))) * 0.82
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(AppTheme.pink.opacity(intensity))
            .frame(width: 46, height: 46)
            .overlay {
                if count > 0 {
                    Text(count.formatted())
                        .font(.caption2.bold())
                        .foregroundStyle(intensity > 0.55 ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
            .help("\(count.formatted()) reactions")
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

private struct BrandedMenuLabel: View {
    let icon: String?
    let title: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.bold())
                .opacity(0.7)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .shadow(color: colors[0].opacity(0.2), radius: 10, y: 4)
    }
}

private struct FilterPillLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.pink)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.caption2.bold())
                .foregroundStyle(AppTheme.purple.opacity(0.7))
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [AppTheme.purple.opacity(0.12), AppTheme.pink.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.purple.opacity(0.45), AppTheme.pink.opacity(0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        }
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
    }
}
