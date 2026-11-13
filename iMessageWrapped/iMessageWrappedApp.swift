import SwiftUI

@main
struct iMessageWrappedApp: App {
    @StateObject private var appModel = AppModel()

    // Unit tests run inside this app; skip the UI so tests never read the real Messages data.
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                EmptyView()
            } else {
                RootView()
                    .environmentObject(appModel)
                    .frame(minWidth: 900, minHeight: 620)
            }
        }
        .defaultSize(width: 1180, height: 760)
    }
}
