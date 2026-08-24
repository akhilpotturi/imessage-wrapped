import SwiftUI

// MARK: - Activity and reaction dynamics

extension ConversationDetailView {
    var dynamicsFilters: some View {
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

    var dynamicsHeatMap: some View {
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

}

private struct DynamicsPerson: Identifiable {
    let id: String
    let name: String
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
