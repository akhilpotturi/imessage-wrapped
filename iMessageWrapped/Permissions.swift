import Foundation
import AppKit

enum Permissions {
    static var messagesDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages/chat.db")
    }

    static func hasFullDiskAccessForMessagesDB() -> Bool {
        do {
            let handle = try FileHandle(forReadingFrom: messagesDBURL)
            try handle.close()
            return true
        } catch {
            return false
        }
    }

    static func openFullDiskAccessSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }

    }

    static func openContactsSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { _, _ in }
        NSApplication.shared.terminate(nil)
    }
}
