import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if appModel.permissionGranted {
                DashboardShell()
            } else {
                PermissionView()
            }
        }
        .task {
            await appModel.load()
        }
    }
}

private struct PermissionView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            PlayfulBackground()

            VStack(spacing: 24) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 104)
                    .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 30))
                    .shadow(color: AppTheme.pink.opacity(0.3), radius: 24, y: 12)

                VStack(spacing: 8) {
                    Text("Your messages, understood")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                    Text("Colorful insights, entirely on your Mac.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ColorfulCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Your message data never leaves this device", systemImage: "lock.shield.fill")
                        Label("The Messages database is always opened read-only", systemImage: "eye.fill")
                        Label("You control any future AI features separately", systemImage: "sparkles")
                    }
                }

                Text("macOS requires Full Disk Access before the app can read your Messages database.")
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Open Full Disk Access Settings") {
                        Permissions.openFullDiskAccessSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)

                    Button("Relaunch App") {
                        Permissions.relaunchApp()
                    }
                }

                Text("After enabling access, relaunch the app for macOS to apply the permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardShell: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showsAllDirectChats = false
    @State private var showsAllGroupChats = false

    private var visibleDirectChats: ArraySlice<ConversationSummary> {
        appModel.directChats.prefix(showsAllDirectChats ? appModel.directChats.count : 5)
    }

    private var visibleGroupChats: ArraySlice<ConversationSummary> {
        appModel.groupChats.prefix(showsAllGroupChats ? appModel.groupChats.count : 5)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { appModel.selection },
                set: { selection in
                    Task { await appModel.select(selection) }
                }
            )) {
                NavigationLink(value: SidebarSelection.overview) {
                    Label("Overview", systemImage: "chart.bar.xaxis")
                }

                Section("Direct Messages") {
                    ForEach(visibleDirectChats) { conversation in
                        NavigationLink(value: SidebarSelection.conversation(conversation.id)) {
                            ConversationRow(conversation: conversation)
                        }
                    }

                    if appModel.directChats.count > 5 {
                        SidebarExpansionButton(
                            isExpanded: showsAllDirectChats,
                            hiddenCount: appModel.directChats.count - 5
                        ) {
                            withAnimation {
                                showsAllDirectChats.toggle()
                            }
                        }
                    }
                }

                Section("Group Chats") {
                    ForEach(visibleGroupChats) { conversation in
                        NavigationLink(value: SidebarSelection.conversation(conversation.id)) {
                            ConversationRow(conversation: conversation)
                        }
                    }

                    if appModel.groupChats.count > 5 {
                        SidebarExpansionButton(
                            isExpanded: showsAllGroupChats,
                            hiddenCount: appModel.groupChats.count - 5
                        ) {
                            withAnimation {
                                showsAllGroupChats.toggle()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [AppTheme.purple.opacity(0.10), AppTheme.cyan.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("Messages")
            .frame(minWidth: 250)
        } detail: {
            Group {
                switch appModel.selection {
                case .overview, .none:
                    OverviewView()
                case .conversation:
                    if let analytics = appModel.selectedAnalytics {
                        ConversationDetailView(analytics: analytics)
                    } else {
                        ProgressView()
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await appModel.load() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(appModel.isLoading)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let warning = appModel.contactWarning {
                HStack {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                    Text(warning)
                    Spacer()
                    Button("Open Contact Settings") {
                        Permissions.openContactsSettings()
                    }
                }
                .font(.callout)
                .padding(12)
                .background(.orange.opacity(0.15))
            }
        }
        .overlay {
            if appModel.isLoading {
                LoadingView(message: appModel.loadingMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let error = appModel.errorMessage {
                ContentUnavailableView(
                    "Couldn’t Load Messages",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .background(.background)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appModel.isLoading)
    }
}

private struct SidebarExpansionButton: View {
    let isExpanded: Bool
    let hiddenCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                isExpanded ? "Show less" : "Show \(hiddenCount) more",
                systemImage: isExpanded ? "chevron.up" : "chevron.down"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.purple)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        HStack {
            Image(systemName: conversation.kind == .group ? "person.3.fill" : "person.fill")
                .foregroundStyle(conversation.kind == .group ? AppTheme.pink : AppTheme.purple)
            Text(conversation.title)
                .lineLimit(1)
            Spacer()
            Text(conversation.messageCount, format: .number.notation(.compactName))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LoadingView: View {
    let message: String
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(AppTheme.purple.opacity(0.32 - Double(index) * 0.07), lineWidth: 3)
                            .frame(width: 74, height: 74)
                            .scaleEffect(isPulsing ? 1.7 + CGFloat(index) * 0.22 : 0.72)
                            .opacity(isPulsing ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.45)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.22),
                                value: isPulsing
                            )
                    }

                    Image(systemName: "message.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(AppTheme.heroGradient, in: Circle())
                        .scaleEffect(isPulsing ? 1.06 : 0.94)
                        .animation(
                            .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }

                VStack(spacing: 7) {
                    Text(message)
                        .font(.title2.bold())
                    Text("Crunching the numbers locally…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(42)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            .shadow(color: AppTheme.purple.opacity(0.22), radius: 32, y: 16)
        }
        .onAppear {
            isPulsing = true
        }
    }
}
