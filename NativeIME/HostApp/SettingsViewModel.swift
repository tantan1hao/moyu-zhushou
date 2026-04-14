import AppKit
import Foundation
import UniformTypeIdentifiers
import NovelIMECore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var state: NovelIMEPersistedState = .default
    @Published private(set) var statusText = "未选择稿源"
    @Published private(set) var progressText = "未开始"
    @Published private(set) var sourceFilePath = ""
    @Published private(set) var allowedAppsText = "Microsoft Word, WPS Writer"

    private let stateStore = NovelIMEStateStore()
    private let documentLoader = NovelDocumentLoader()
    private var refreshTimer: Timer?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let currentState = stateStore.load()
        state = currentState
        sourceFilePath = currentState.resolvedSourceURL?.path ?? "未选择"
        let allowedBundleIDs = currentState.allowedBundleIDs.isEmpty
            ? NovelIMEConstants.defaultAllowedBundleIDs
            : currentState.allowedBundleIDs
        allowedAppsText = allowedBundleIDs
            .map(NovelIMEConstants.displayName(for:))
            .joined(separator: ", ")

        guard let sourceURL = currentState.resolvedSourceURL else {
            statusText = currentState.armed ? "Armed，但未选择稿源" : "Off"
            progressText = "未开始"
            return
        }

        do {
            let document = try documentLoader.load(from: sourceURL)
            let engine = NovelPlaybackEngine(document: document, state: currentState)
            let snapshot = engine.progressSnapshot()
            progressText = snapshot.formattedProgress
            if snapshot.eofReached {
                statusText = "EOF"
            } else {
                statusText = currentState.armed ? "Armed" : "Off"
            }
        } catch {
            statusText = "稿源读取失败"
            progressText = "未开始"
        }
    }

    func toggleArmed() {
        do {
            try stateStore.update { state in
                state.armed.toggle()
            }
            refresh()
        } catch {
            statusText = "状态写入失败"
        }
    }

    func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .rtf]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择稿源"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try stateStore.update { state in
                state.sourceFileURL = url.path
                state.paragraphIndex = 0
                state.charIndex = 0
                state.eofReached = false
            }
            refresh()
        } catch {
            statusText = "稿源写入失败"
        }
    }

    func revealInputMethodsFolder() {
        let folderURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }
}
