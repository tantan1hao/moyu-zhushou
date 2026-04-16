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
    private let refreshQueue = DispatchQueue(label: "com.tantan1hao.moyuassistant.settings-refresh", qos: .userInitiated)
    private let persistenceQueue = DispatchQueue(label: "com.tantan1hao.moyuassistant.settings-persist", qos: .userInitiated)

    private var refreshTimer: Timer?
    private var refreshRequestID = 0
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var pendingForceDocumentReload = false
    private var cachedDocument: NovelDocument?
    private var cachedDocumentSourcePath: String?
    private var cachedDocumentModificationDate: Date?
    private var isChoosingSourceFile = false
    private weak var openPanel: NSOpenPanel?

    init() {
        refresh(forceDocumentReload: true)
        startAutoRefresh()
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        timer.tolerance = 0.3
        refreshTimer = timer
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh(forceDocumentReload: Bool = false) {
        guard !isChoosingSourceFile else {
            return
        }

        refreshRequestID += 1
        pendingRefresh = true
        pendingForceDocumentReload = pendingForceDocumentReload || forceDocumentReload

        guard !refreshInFlight else {
            return
        }

        refreshInFlight = true
        pendingRefresh = false
        let requestID = refreshRequestID
        let effectiveForceDocumentReload = pendingForceDocumentReload
        pendingForceDocumentReload = false
        let existingCache = DocumentCache(
            document: cachedDocument,
            sourcePath: cachedDocumentSourcePath,
            modificationDate: cachedDocumentModificationDate
        )
        let stateStore = stateStore
        let sourceSecurityStore = sourceSecurityStore
        let documentLoader = documentLoader

        refreshQueue.async { [weak self] in
            let result = Self.computeRefreshResult(
                stateStore: stateStore,
                sourceSecurityStore: sourceSecurityStore,
                documentLoader: documentLoader,
                existingCache: existingCache,
                forceDocumentReload: effectiveForceDocumentReload
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.refreshInFlight = false
                if requestID == self.refreshRequestID {
                    self.apply(result: result)
                }
                if self.pendingRefresh {
                    self.refresh(forceDocumentReload: self.pendingForceDocumentReload)
                }
            }
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
        guard !isChoosingSourceFile else {
            return
        }

        stopAutoRefresh()
        isChoosingSourceFile = true

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .rtf]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择稿源"
        panel.title = "选择稿源"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        openPanel = panel

        NSApp.activate(ignoringOtherApps: true)

        panel.begin { [weak self, weak panel] response in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.openPanel = nil
                self.isChoosingSourceFile = false
                self.startAutoRefresh()

                guard response == .OK, let url = panel?.url else {
                    self.refresh(forceDocumentReload: true)
                    return
                }

                self.persistSelectedSourceFile(url)
            }
        }
    }

    private func persistSelectedSourceFile(_ url: URL) {
        statusText = "正在保存稿源..."
        sourceFilePath = url.path

        let stateStore = stateStore
        let sourceSecurityStore = sourceSecurityStore
        persistenceQueue.async { [weak self] in
            do {
                try sourceSecurityStore.saveBookmark(for: url)
                let savedState = try stateStore.update { state in
                    state.sourceFileURL = url.path
                    state.paragraphIndex = 0
                    state.charIndex = 0
                    state.eofReached = false
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    self.state = savedState
                    self.refresh(forceDocumentReload: true)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.statusText = "稿源写入失败"
                }
            }
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

    private func apply(result: RefreshResult) {
        state = result.state
        statusText = result.statusText
        progressText = result.progressText
        sourceFilePath = result.sourceFilePath
        allowedAppsText = result.allowedAppsText
        installStatusText = result.installStatusText
        inputSourceStatusText = result.inputSourceStatusText
        nextStepText = result.nextStepText
        cachedDocument = result.documentCache?.document
        cachedDocumentSourcePath = result.documentCache?.sourcePath
        cachedDocumentModificationDate = result.documentCache?.modificationDate
    }
}

private extension SettingsViewModel {
    struct DocumentCache {
        let document: NovelDocument?
        let sourcePath: String?
        let modificationDate: Date?
    }

    struct InstallationStatusSnapshot {
        let installStatusText: String
        let inputSourceStatusText: String
        let nextStepText: String
    }

    struct RefreshResult {
        let state: NovelIMEPersistedState
        let statusText: String
        let progressText: String
        let sourceFilePath: String
        let allowedAppsText: String
        let installStatusText: String
        let inputSourceStatusText: String
        let nextStepText: String
        let documentCache: DocumentCache?
    }

    nonisolated static func computeRefreshResult(
        stateStore: NovelIMEStateStore,
        sourceSecurityStore: NovelSourceSecurityStore,
        documentLoader: NovelDocumentLoader,
        existingCache: DocumentCache,
        forceDocumentReload: Bool
    ) -> RefreshResult {
        let currentState = stateStore.load()
        let installationStatus = refreshInstallationStatus()
        let sourceFilePath = currentState.resolvedSourceURL?.path ?? "未选择"
        let allowedBundleIDs = currentState.allowedBundleIDs.isEmpty
            ? NovelIMEConstants.defaultAllowedBundleIDs
            : currentState.allowedBundleIDs
        let allowedAppsText = allowedBundleIDs
            .map(NovelIMEConstants.displayName(for:))
            .joined(separator: ", ")

        guard let sourceURL = currentState.resolvedSourceURL else {
            return RefreshResult(
                state: currentState,
                statusText: currentState.armed ? "Armed 已开启，但未选择稿源" : "Armed 已关闭",
                progressText: "未开始",
                sourceFilePath: sourceFilePath,
                allowedAppsText: allowedAppsText,
                installStatusText: installationStatus.installStatusText,
                inputSourceStatusText: installationStatus.inputSourceStatusText,
                nextStepText: installationStatus.nextStepText,
                documentCache: nil
            )
        }

        do {
            let cacheResult = try sourceSecurityStore.withAccessToSourceURL(fallback: sourceURL) { securedSourceURL in
                let modificationDate = try? securedSourceURL
                    .resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                let shouldReuseCache = !forceDocumentReload
                    && existingCache.sourcePath == securedSourceURL.path
                    && existingCache.modificationDate == modificationDate

                if shouldReuseCache, let cachedDocument = existingCache.document {
                    return DocumentCache(
                        document: cachedDocument,
                        sourcePath: securedSourceURL.path,
                        modificationDate: modificationDate
                    )
                }

                let document = try documentLoader.load(from: securedSourceURL)
                return DocumentCache(
                    document: document,
                    sourcePath: securedSourceURL.path,
                    modificationDate: modificationDate
                )
            }

            guard let cacheResult, let document = cacheResult.document else {
                return RefreshResult(
                    state: currentState,
                    statusText: currentState.armed ? "Armed 已开启，但未选择稿源" : "Armed 已关闭",
                    progressText: "未开始",
                    sourceFilePath: sourceFilePath,
                    allowedAppsText: allowedAppsText,
                    installStatusText: installationStatus.installStatusText,
                    inputSourceStatusText: installationStatus.inputSourceStatusText,
                    nextStepText: installationStatus.nextStepText,
                    documentCache: nil
                )
            }

            let engine = NovelPlaybackEngine(document: document, state: currentState)
            let snapshot = engine.progressSnapshot()
            let statusText = snapshot.eofReached ? "EOF" : (currentState.armed ? "Armed 已开启" : "Armed 已关闭")

            return RefreshResult(
                state: currentState,
                statusText: statusText,
                progressText: snapshot.formattedProgress,
                sourceFilePath: sourceFilePath,
                allowedAppsText: allowedAppsText,
                installStatusText: installationStatus.installStatusText,
                inputSourceStatusText: installationStatus.inputSourceStatusText,
                nextStepText: installationStatus.nextStepText,
                documentCache: cacheResult
            )
        } catch {
            return RefreshResult(
                state: currentState,
                statusText: "稿源读取失败",
                progressText: "未开始",
                sourceFilePath: sourceFilePath,
                allowedAppsText: allowedAppsText,
                installStatusText: installationStatus.installStatusText,
                inputSourceStatusText: installationStatus.inputSourceStatusText,
                nextStepText: installationStatus.nextStepText,
                documentCache: nil
            )
        }
    }

    nonisolated static func refreshInstallationStatus() -> InstallationStatusSnapshot {
        let fileManager = FileManager.default
        let systemInstallPath = "/Library/Input Methods/MoyuAssistant.app"
        let userInstallPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods/MoyuAssistant.app", isDirectory: true)
            .path

        let systemInstalled = fileManager.fileExists(atPath: systemInstallPath)
        let userInstalled = fileManager.fileExists(atPath: userInstallPath)

        let installStatusText: String
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
        let inputSourceStatusText = statusParts.joined(separator: " / ")

        let nextStepText: String
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

        return InstallationStatusSnapshot(
            installStatusText: installStatusText,
            inputSourceStatusText: inputSourceStatusText,
            nextStepText: nextStepText
        )
    }

    nonisolated static func inputSourceVisibleInTIS() -> Bool {
        withMainThreadTISAccess {
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
    }

    nonisolated static func inputSourceExistsInPreferences(key: String) -> Bool {
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

    nonisolated static func tisStringProperty(_ source: TISInputSource, key: CFString) -> String {
        guard let value = tisObjectProperty(source, key: key) else {
            return ""
        }
        return value as? String ?? ""
    }

    nonisolated static func tisObjectProperty(_ source: TISInputSource, key: CFString) -> AnyObject? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
    }

    nonisolated static func withMainThreadTISAccess<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }

        return DispatchQueue.main.sync(execute: work)
    }
}
