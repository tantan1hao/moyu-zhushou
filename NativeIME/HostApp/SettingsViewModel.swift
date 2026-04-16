import AppKit
import Carbon
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
    @Published private(set) var installStatusText = "未安装"
    @Published private(set) var inputSourceStatusText = "尚未写入系统启用列表"
    @Published private(set) var nextStepText = "先完成系统级安装，再去“键盘 -> 输入法”手动添加“摸鱼助手”。"

    private let stateStore = NovelIMEStateStore()
    private let sourceSecurityStore = NovelSourceSecurityStore()
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
        refreshInstallationStatus()
        sourceFilePath = currentState.resolvedSourceURL?.path ?? "未选择"
        let allowedBundleIDs = currentState.allowedBundleIDs.isEmpty
            ? NovelIMEConstants.defaultAllowedBundleIDs
            : currentState.allowedBundleIDs
        allowedAppsText = allowedBundleIDs
            .map(NovelIMEConstants.displayName(for:))
            .joined(separator: ", ")

        guard let sourceURL = currentState.resolvedSourceURL else {
            statusText = currentState.armed ? "Armed 已开启，但未选择稿源" : "Armed 已关闭"
            progressText = "未开始"
            return
        }

        do {
            let document: NovelDocument? = try sourceSecurityStore.withAccessToSourceURL(
                fallback: sourceURL
            ) { securedSourceURL in
                try documentLoader.load(from: securedSourceURL)
            }

            guard let document else {
                statusText = currentState.armed ? "Armed 已开启，但未选择稿源" : "Armed 已关闭"
                progressText = "未开始"
                return
            }
            let engine = NovelPlaybackEngine(document: document, state: currentState)
            let snapshot = engine.progressSnapshot()
            progressText = snapshot.formattedProgress
            if snapshot.eofReached {
                statusText = "EOF"
            } else {
                statusText = currentState.armed ? "Armed 已开启" : "Armed 已关闭"
            }
        } catch {
            statusText = "稿源读取失败"
            progressText = "未开始"
        }
    }

    private func refreshInstallationStatus() {
        let fileManager = FileManager.default
        let systemInstallPath = "/Library/Input Methods/MoyuAssistant.app"
        let userInstallPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods/MoyuAssistant.app", isDirectory: true)
            .path

        let systemInstalled = fileManager.fileExists(atPath: systemInstallPath)
        let userInstalled = fileManager.fileExists(atPath: userInstallPath)

        if systemInstalled {
            installStatusText = "系统级安装已就绪：\(systemInstallPath)"
        } else if userInstalled {
            installStatusText = "检测到开发安装：\(userInstallPath)"
        } else {
            installStatusText = "未检测到已安装的输入法 bundle"
        }

        let enabledInPreferences = inputSourceExistsInPreferences(key: "AppleEnabledInputSources")
        let selectedInPreferences = inputSourceExistsInPreferences(key: "AppleSelectedInputSources")
        let visibleInTIS = inputSourceVisibleInTIS()

        var statusParts: [String] = []
        statusParts.append(visibleInTIS ? "系统已注册" : "系统未注册")
        statusParts.append(enabledInPreferences ? "已加入启用列表" : "未加入启用列表")
        statusParts.append(selectedInPreferences ? "当前已选中" : "当前未选中")
        inputSourceStatusText = statusParts.joined(separator: " / ")

        if systemInstalled {
            if selectedInPreferences {
                nextStepText = "现在直接去菜单栏输入法图标或按 Control + Space，手动切到“摸鱼助手”，然后在本窗口选择 txt 并开启 Armed。"
            } else if enabledInPreferences || visibleInTIS {
                nextStepText = "下一步去“键盘 -> 输入法”手动添加或切换“摸鱼助手”。如果这一页没刷新，先彻底退出系统设置再打开；仍然没有时，再注销/重新登录一次。"
            } else {
                nextStepText = "系统级 app 已安装，但当前会话还没完全认到它。先打开“键盘 -> 输入法”检查；如果看不到，退出系统设置后重开，仍无则注销/重新登录一次。"
            }
        } else if userInstalled {
            nextStepText = "当前是开发态安装。首次使用建议改走系统级 pkg：运行 scripts/build_input_method_pkg.sh，安装到 /Library/Input Methods 后再手动添加输入法。"
        } else {
            nextStepText = "先运行 scripts/build_input_method_pkg.sh 生成并安装系统级 pkg。安装后去“键盘 -> 输入法”手动添加“摸鱼助手”。"
        }
    }

    private func inputSourceVisibleInTIS() -> Bool {
        let sourceList = TISCreateInputSourceList(nil, true).takeRetainedValue() as NSArray

        for item in sourceList {
            let source = unsafeBitCast(item, to: TISInputSource.self)
            let inputSourceID = tisStringProperty(source, key: kTISPropertyInputSourceID)
            let bundleID = tisStringProperty(source, key: kTISPropertyBundleID)
            if inputSourceID == NovelIMEConstants.inputSourceIdentifier
                || inputSourceID == NovelIMEConstants.inputModeIdentifier
                || bundleID == NovelIMEConstants.hostBundleIdentifier
            {
                return true
            }
        }

        return false
    }

    private func inputSourceExistsInPreferences(key: String) -> Bool {
        guard let values = CFPreferencesCopyAppValue(key as CFString, "com.apple.HIToolbox" as CFString) else {
            return false
        }

        guard let entries = values as? [[String: Any]] else {
            return false
        }

        for entry in entries {
            let bundleID = entry["Bundle ID"] as? String
            let inputMode = entry["Input Mode"] as? String
            let inputSourceID = entry["Input Source ID"] as? String
            if bundleID == NovelIMEConstants.hostBundleIdentifier
                || inputMode == NovelIMEConstants.inputModeIdentifier
                || inputSourceID == NovelIMEConstants.inputSourceIdentifier
            {
                return true
            }
        }

        return false
    }

    private func tisStringProperty(_ source: TISInputSource, key: CFString) -> String {
        guard let value = tisObjectProperty(source, key: key) else {
            return ""
        }
        return value as? String ?? ""
    }

    private func tisObjectProperty(_ source: TISInputSource, key: CFString) -> AnyObject? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
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
            try sourceSecurityStore.saveBookmark(for: url)
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

    func revealInstalledInputMethod() {
        let fileManager = FileManager.default
        let systemAppPath = "/Library/Input Methods/MoyuAssistant.app"
        let userAppPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods/MoyuAssistant.app", isDirectory: true)
            .path
        let targetPath = fileManager.fileExists(atPath: systemAppPath) ? systemAppPath : userAppPath
        NSWorkspace.shared.selectFile(targetPath, inFileViewerRootedAtPath: "/")
    }

    func openKeyboardInputSources() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealInputMethodsFolder() {
        let systemFolder = "/Library/Input Methods"
        let homeFolder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .path
        let targetFolder = FileManager.default.fileExists(atPath: systemFolder) ? systemFolder : homeFolder
        let folderURL = URL(fileURLWithPath: targetFolder, isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }
}
