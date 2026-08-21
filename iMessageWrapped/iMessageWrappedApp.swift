import SwiftUI

@main
struct iMessageWrappedApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)
    }
}
