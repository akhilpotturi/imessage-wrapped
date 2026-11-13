import AppKit
import SwiftUI

// MARK: - Message samples

extension ConversationDetailView {
    var messageSamplesWorkspace: some View {
        ColorfulCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message highlights")
                            .font(.title2.bold())
                        Text("A few memorable messages from this conversation")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        refreshMessageHighlights()
                    } label: {
                        Label("Refresh attachments", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.isMessageHighlightsLoading)
                    .help("Reload messages and check for newly downloaded attachments")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Message date", systemImage: "calendar")
                        .font(.headline)
                        .foregroundStyle(AppTheme.purple)
                        .help("Limits highlights based on when each message was sent.")

                    HStack(spacing: 8) {
                        ForEach(AnalyticsRange.allCases) { range in
                            Button {
                                messageHighlightsRange = range
                                refreshMessageHighlights()
                            } label: {
                                Text(range.title)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(
                                        messageHighlightsRange == range
                                            ? .white
                                            : AppTheme.purple
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background {
                                        if messageHighlightsRange == range {
                                            RoundedRectangle(cornerRadius: 13)
                                                .fill(AppTheme.heroGradient)
                                        } else {
                                            RoundedRectangle(cornerRadius: 13)
                                                .fill(AppTheme.purple.opacity(0.08))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(
                                "Show messages sent during \(range.periodDescription)."
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(MessageSampleMetric.allCases) { metric in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                messageSampleMetric = metric
                            }
                            appModel.clearMessageContext()
                        } label: {
                            Label(metric.title, systemImage: metric.systemImage)
                                .font(.subheadline.bold())
                                .foregroundStyle(
                                    messageSampleMetric == metric ? .white : AppTheme.purple
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background {
                                    if messageSampleMetric == metric {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(AppTheme.heroGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(AppTheme.purple.opacity(0.08))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(metric.helpText)
                    }
                }

                if highlightedMessages.isEmpty, !appModel.isMessageHighlightsLoading {
                    ContentUnavailableView(
                        "No matching messages",
                        systemImage: "quote.bubble",
                        description: Text(messageSampleMetric.emptyDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(highlightedMessages.enumerated()), id: \.element.id) {
                            index,
                            message in
                            MessageHighlightRow(
                                rank: index + 1,
                                message: message,
                                metric: messageSampleMetric,
                                isExpanded: appModel.selectedContextMessageID == message.id
                            ) {
                                appModel.showMessageContext(messageID: message.id)
                            }

                            if appModel.selectedContextMessageID == message.id {
                                MessageContextPanel(
                                    messages: appModel.messageContext,
                                    selectedMessageID: message.id,
                                    isLoading: appModel.isMessageContextLoading
                                ) {
                                    appModel.clearMessageContext()
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity
                                    )
                                )
                            }
                        }
                    }
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.86),
                        value: appModel.selectedContextMessageID
                    )
                }
            }
        }
        .overlay {
            if appModel.isMessageHighlightsLoading {
                SectionLoadingOverlay(title: "Finding message highlights")
            }
        }
    }

    func refreshMessageHighlights() {
        appModel.clearMessageContext()
        appModel.scheduleMessageHighlightsAnalysis(range: messageHighlightsRange)
    }

    private var highlightedMessages: [MessageHighlight] {
        let eligible = appModel.messageHighlights.filter(messageSampleMetric.isEligible)
        return Array(
            eligible.sorted {
                let left = messageSampleMetric.value(for: $0)
                let right = messageSampleMetric.value(for: $1)
                if left == right {
                    return $0.date > $1.date
                }
                return left > right
            }.prefix(5)
        )
    }
}

enum MessageSampleMetric: String, CaseIterable, Identifiable {
    case mostReacted
    case mostLoved
    case mostLaughedAt
    case longest

    var id: Self { self }

    var title: String {
        switch self {
        case .mostReacted: "Most reacted"
        case .mostLoved: "Most loved"
        case .mostLaughedAt: "Most laughed at"
        case .longest: "Longest"
        }
    }

    var systemImage: String {
        switch self {
        case .mostReacted: "heart.circle.fill"
        case .mostLoved: "heart.fill"
        case .mostLaughedAt: "face.smiling.inverse"
        case .longest: "text.alignleft"
        }
    }

    var helpText: String {
        switch self {
        case .mostReacted: "The five messages with the most active reactions of every type."
        case .mostLoved: "The five messages with the most active heart reactions."
        case .mostLaughedAt: "The five messages with the most active laugh reactions."
        case .longest: "The five text messages with the most characters."
        }
    }

    var emptyDescription: String {
        switch self {
        case .mostReacted, .mostLoved, .mostLaughedAt:
            "This conversation has no active reactions in this category."
        case .longest:
            "This conversation has no text messages to show."
        }
    }

    func isEligible(_ message: MessageHighlight) -> Bool {
        switch self {
        case .mostReacted:
            return message.totalReactions > 0
        case .mostLoved:
            return message.reactionCount(for: .loved) > 0
        case .mostLaughedAt:
            return message.reactionCount(for: .laughed) > 0
        case .longest:
            return !message.text.isEmpty
        }
    }

    func value(for message: MessageHighlight) -> Int {
        switch self {
        case .mostReacted:
            return message.totalReactions
        case .mostLoved:
            return message.reactionCount(for: .loved)
        case .mostLaughedAt:
            return message.reactionCount(for: .laughed)
        case .longest:
            return message.text.count
        }
    }
}

private struct MessageHighlightRow: View {
    let rank: Int
    let message: MessageHighlight
    let metric: MessageSampleMetric
    let isExpanded: Bool
    let toggleContext: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("#\(rank)")
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(rank <= 3 ? AppTheme.pink : .secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 10) {
                Button(action: toggleContext) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(message.senderName)
                                .font(.headline)
                            if message.isCurrentUser {
                                Text("YOU")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.pink, in: Capsule())
                            }
                            Spacer()
                            Text(
                                message.date.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Image(
                                systemName: isExpanded
                                    ? "chevron.up.circle.fill"
                                    : "chevron.down.circle"
                            )
                            .foregroundStyle(AppTheme.purple)
                        }

                        if !message.text.isEmpty {
                            Text("“\(message.text)”")
                                .font(.body)
                                .lineLimit(5)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    isExpanded
                        ? "Hide conversation context"
                        : "Show conversation context"
                )

                if !message.attachments.isEmpty {
                    MessageAttachmentGrid(attachments: message.attachments)
                }

                HStack(spacing: 8) {
                    ForEach(ReactionType.allCases.filter { $0 != .all }) { type in
                        let count = message.reactionCount(for: type)
                        if count > 0 {
                            Text("\(type.symbol) \(count)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.pink.opacity(0.1), in: Capsule())
                        }
                    }

                    if message.totalReactions == 0 {
                        Text("\(message.text.count.formatted()) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.purple.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .help("\(metric.helpText) Click to show five messages before and after.")
    }
}

private struct MessageContextPanel: View {
    let messages: [MessageContextEntry]
    let selectedMessageID: Int64
    let isLoading: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Conversation context", systemImage: "text.bubble.fill")
                    .font(.headline)
                Text("Up to 5 messages before and after")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Close context")
            }

            ZStack {
                if isLoading {
                    MessageContextLoadingView()
                        .transition(.opacity)
                } else {
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(messages) { message in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(message.senderName)
                                        .font(.caption.bold())
                                        .foregroundStyle(
                                            message.isCurrentUser
                                                ? AppTheme.pink
                                                : AppTheme.purple
                                        )
                                        .frame(width: 105, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 7) {
                                        if !message.text.isEmpty {
                                            Text(message.text)
                                                .textSelection(.enabled)
                                        }
                                        if !message.attachments.isEmpty {
                                            MessageAttachmentGrid(
                                                attachments: message.attachments,
                                                compact: true
                                            )
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(
                                        message.date.formatted(
                                            date: .omitted,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(9)
                                .background(
                                    message.id == selectedMessageID
                                        ? AppTheme.orange.opacity(0.16)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay(alignment: .leading) {
                                    if message.id == selectedMessageID {
                                        Capsule()
                                            .fill(AppTheme.orange)
                                            .frame(width: 4)
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 180, maxHeight: 420, alignment: .top)
            .animation(.easeInOut(duration: 0.24), value: isLoading)
        }
        .padding(16)
        .background(AppTheme.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.cyan.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct MessageContextLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 10) {
                    Capsule()
                        .fill(AppTheme.purple.opacity(0.12))
                        .frame(width: 78, height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.purple.opacity(0.09))
                        .frame(height: index.isMultiple(of: 2) ? 28 : 42)
                    Capsule()
                        .fill(AppTheme.purple.opacity(0.08))
                        .frame(width: 38, height: 8)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading conversation context")
    }
}
