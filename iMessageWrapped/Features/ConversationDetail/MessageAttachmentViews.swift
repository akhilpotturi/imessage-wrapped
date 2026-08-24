import AppKit
import Photos
import SwiftUI

struct MessageAttachmentGrid: View {
    let attachments: [MessageAttachment]
    var compact = false

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compact ? 105 : 145), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(attachments) { attachment in
                MessageAttachmentPreview(attachment: attachment, compact: compact)
            }
        }
    }
}

private struct MessageAttachmentPreview: View {
    private enum LookupState {
        case idle
        case locating
        case notFound
    }

    let attachment: MessageAttachment
    let compact: Bool
    @State private var locatedURL: URL?
    @State private var lookupState: LookupState = .idle

    init(attachment: MessageAttachment, compact: Bool) {
        self.attachment = attachment
        self.compact = compact
        let savedPath = UserDefaults.standard.string(
            forKey: "message-attachment-path-\(attachment.id)"
        )
        _locatedURL = State(
            initialValue: savedPath.map { URL(fileURLWithPath: $0) }
        )
    }

    private var savedPathKey: String {
        "message-attachment-path-\(attachment.id)"
    }

    private var image: NSImage? {
        guard let fileURL = availableURL else { return nil }
        return NSImage(contentsOf: fileURL)
    }

    private var availableURL: URL? {
        if let locatedURL, FileManager.default.fileExists(atPath: locatedURL.path) {
            return locatedURL
        }
        guard let fileURL = attachment.fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    private var systemImage: String {
        if lookupState == .notFound {
            return "exclamationmark.icloud.fill"
        }
        if availableURL == nil {
            return "icloud.and.arrow.down"
        }
        if attachment.mimeType.hasPrefix("video/") {
            return "video.fill"
        }
        if attachment.mimeType.hasPrefix("audio/") {
            return "waveform"
        }
        return "doc.fill"
    }

    var body: some View {
        Button {
            if let fileURL = availableURL {
                NSWorkspace.shared.open(fileURL)
            } else if lookupState == .notFound {
                chooseLocalFile()
            } else {
                locateAndOpen()
            }
        } label: {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: compact ? 72 : 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        attachmentLabel
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    if lookupState == .locating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: systemImage)
                            .font(compact ? .body : .title2)
                            .foregroundStyle(AppTheme.purple)
                    }
                    Text(attachment.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    if lookupState == .notFound {
                        Text("Choose file…")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.pink)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: compact ? 54 : 74)
                .background(
                    AppTheme.purple.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(lookupState == .locating)
        .help(attachmentHelp)
    }

    private func locateAndOpen() {
        lookupState = .locating
        Task {
            let attachment = attachment
            let messagesResult = await Task.detached {
                locateDownloadedAttachment(attachment)
            }.value
            let result = if let messagesResult {
                messagesResult
            } else {
                await locatePhotoAttachment(attachment)
            }
            locatedURL = result
            if let result {
                lookupState = .idle
                NSWorkspace.shared.open(result)
            } else {
                lookupState = .notFound
            }
        }
    }

    private var attachmentHelp: String {
        if availableURL != nil {
            return "Open \(attachment.displayName)"
        }
        if lookupState == .notFound {
            return "No matching file was found in Messages or Photos. Click to choose it manually."
        }
        return "Search Messages and Photos for \(attachment.displayName)"
    }

    private func chooseLocalFile() {
        let panel = NSOpenPanel()
        panel.title = "Locate \(attachment.displayName)"
        panel.message = "Choose the local file that belongs to this Messages attachment."
        panel.prompt = "Use Attachment"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.nameFieldStringValue = attachment.displayName

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        locatedURL = selectedURL
        lookupState = .idle
        UserDefaults.standard.set(selectedURL.path, forKey: savedPathKey)
    }

    private var attachmentLabel: some View {
        Text(attachment.displayName)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(7)
            .background(.black.opacity(0.55))
    }
}

private nonisolated func locateDownloadedAttachment(
    _ attachment: MessageAttachment
) -> URL? {
    let messagesRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Messages")
    let normalizedGUID = attachment.guid
        .replacingOccurrences(of: "at_0_", with: "")
        .lowercased()
    let expectedFilename = attachment.fileURL?.lastPathComponent
    var newestNameMatch: (url: URL, date: Date)?

    guard let enumerator = FileManager.default.enumerator(
        at: messagesRoot,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    for case let fileURL as URL in enumerator {
        let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .contentModificationDateKey]
        )
        guard values?.isRegularFile == true else { continue }

        if !normalizedGUID.isEmpty,
           fileURL.path.lowercased().contains(normalizedGUID) {
            return fileURL
        }
        let matchesDisplayName = fileURL.lastPathComponent
            .localizedCaseInsensitiveCompare(attachment.displayName) == .orderedSame
        let matchesExpectedName = expectedFilename.map {
            fileURL.lastPathComponent.localizedCaseInsensitiveCompare($0) == .orderedSame
        } ?? false
        guard matchesDisplayName || matchesExpectedName else {
            continue
        }
        let date = values?.contentModificationDate ?? .distantPast
        if date > (newestNameMatch?.date ?? .distantPast) {
            newestNameMatch = (fileURL, date)
        }
    }
    return newestNameMatch?.url
}

@MainActor
private func locatePhotoAttachment(
    _ attachment: MessageAttachment
) async -> URL? {
    let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    guard authorization == .authorized || authorization == .limited else {
        return nil
    }

    let fetchOptions = PHFetchOptions()
    if attachment.mimeType.hasPrefix("video/") {
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.video.rawValue
        )
    } else if attachment.mimeType.hasPrefix("image/") {
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
    }

    let assets = PHAsset.fetchAssets(with: fetchOptions)
    var bestMatch: (resource: PHAssetResource, distance: TimeInterval)?
    assets.enumerateObjects { asset, _, _ in
        for resource in PHAssetResource.assetResources(for: asset) {
            let matchesName = resource.originalFilename
                .localizedCaseInsensitiveCompare(attachment.displayName) == .orderedSame
            guard matchesName else { continue }
            let distance = abs(
                (asset.creationDate ?? .distantPast)
                    .timeIntervalSince(attachment.messageDate)
            )
            if distance < (bestMatch?.distance ?? .greatestFiniteMagnitude) {
                bestMatch = (resource, distance)
            }
        }
    }
    guard let resource = bestMatch?.resource else { return nil }

    let cacheDirectory = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    )[0]
        .appending(path: "iMessageWrapped/PhotoAttachments", directoryHint: .isDirectory)
        .appending(path: String(attachment.id), directoryHint: .isDirectory)
    do {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    } catch {
        return nil
    }

    let destination = cacheDirectory.appending(path: resource.originalFilename)
    if FileManager.default.fileExists(atPath: destination.path) {
        return destination
    }

    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true
    return await withCheckedContinuation { continuation in
        PHAssetResourceManager.default().writeData(
            for: resource,
            toFile: destination,
            options: options
        ) { error in
            continuation.resume(returning: error == nil ? destination : nil)
        }
    }
}
