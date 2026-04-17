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
    @Published private(set) var allowedAppsText = "TextEdit, Microsoft Word, WPS Writer"
    @Published private(set) var currentInputSourceText = "未知"
    @Published private(set) var inputSourceStatusText = "未校验"

    private let stateStore = NovelIMEStateStore()
    private let documentLoader = NovelDocumentLoader()
    private var refreshTimer: Timer?

    init() {
        NovelDiagnosticLogger.log("settings", "init")
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
        if let currentInputSource = InputSourceRegistrar.currentSelectedInputSource() {
            currentInputSourceText = "\(currentInputSource.localizedName) (\(currentInputSource.inputSourceID))"
        } else {
            currentInputSourceText = "未检测到"
        }
        inputSourceStatusText = InputSourceRegistrar.verifySelection() ? "当前已选中" : "当前未选中"
        let currentInputSourceText = self.currentInputSourceText
        let inputSourceStatusText = self.inputSourceStatusText
        NovelDiagnosticLogger.log(
            "settings",
            "refresh armed=\(currentState.armed) currentInput=\(currentInputSourceText) inputStatus=\(inputSourceStatusText)"
        )

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
        let newArmedState = !state.armed
        do {
            try stateStore.update { state in
                state.armed = newArmedState
            }
            NovelDiagnosticLogger.log("settings", "toggleArmed -> \(newArmedState ? "on" : "off")")
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
            NovelDiagnosticLogger.log("settings", "chooseSourceFile path=\(url.path)")
            refresh()
        } catch {
            statusText = "稿源写入失败"
        }
    }

    func switchToMoyuAssistant() {
        _ = InputSourceRegistrar.enableInputMode()
        _ = InputSourceRegistrar.selectInputMode()
        refresh()
    }

    func revealInputMethodsFolder() {
        let folderURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }
}
