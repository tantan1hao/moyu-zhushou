import AppKit
import InputMethodKit
import NovelIMECore

@objc(NovelInputController)
final class NovelInputController: IMKInputController {
    private let stateStore = NovelIMEStateStore()
    private let sourceSecurityStore = NovelSourceSecurityStore()
    private let documentLoader = NovelDocumentLoader()
    private let inputPolicy = NovelInputPolicy()

    private var currentState: NovelIMEPersistedState = .default
    private var currentDocument: NovelDocument?
    private var runtimeEngine: NovelPlaybackEngine?
    private var lastSourceURL: URL?
    private var lastSourceModificationDate: Date?

    override func activateServer(_ sender: Any!) {
        _ = synchronizeRuntime(forceReloadDocument: true)
    }

    override func deactivateServer(_ sender: Any!) {
        runtimeEngine?.clearPreedit()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else {
            return false
        }

        guard let engine = synchronizeRuntime() else {
            return false
        }

        let action = inputPolicy.action(
            for: key(from: event),
            context: NovelInputContext(
                armed: currentState.armed,
                frontmostBundleID: frontmostBundleIdentifier,
                allowedBundleIDs: currentState.allowedBundleIDs,
                hasRemainingText: engine.hasRemainingText,
                hasPreedit: !engine.preeditBuffer.isEmpty
            )
        )

        switch action {
        case .passThrough:
            return false
        case .rewindPreedit:
            return handleDelete(engine: engine)
        case .commitPreedit:
            return handleReturn(sender, engine: engine)
        case .advancePreedit:
            if !engine.hasRemainingText && engine.preeditBuffer.isEmpty {
                return false
            }

            _ = engine.appendNextCharacter()
            updateComposition()
            return true
        }
    }

    override func commitComposition(_ sender: Any!) {
        _ = commitCurrentPreedit(sender)
    }

    override func composedString(_ sender: Any!) -> Any! {
        guard let engine = runtimeEngine, !engine.preeditBuffer.isEmpty else {
            return nil
        }
        return NSAttributedString(
            string: engine.preeditBuffer,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
    }

    override func originalString(_ sender: Any!) -> NSAttributedString! {
        guard let engine = runtimeEngine, !engine.preeditBuffer.isEmpty else {
            return nil
        }
        return NSAttributedString(string: engine.preeditBuffer)
    }

    override func selectionRange() -> NSRange {
        guard let engine = runtimeEngine else {
            return NSRange(location: 0, length: 0)
        }
        return NSRange(location: engine.preeditBuffer.count, length: 0)
    }

    override func showPreferences(_ sender: Any!) {
        let bundleURL = Bundle.main.bundleURL
        let appURL: URL
        if bundleURL.pathExtension == "app" {
            appURL = bundleURL
        } else {
            appURL = bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = ["--show-settings"]
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }

    private func handleDelete(engine: NovelPlaybackEngine) -> Bool {
        guard !engine.preeditBuffer.isEmpty else {
            return false
        }

        _ = engine.rewindPreedit()
        updateComposition()
        return true
    }

    private func handleReturn(_ sender: Any!, engine: NovelPlaybackEngine) -> Bool {
        commitCurrentPreedit(sender, engine: engine)
    }

    @discardableResult
    private func commitCurrentPreedit(_ sender: Any!, engine: NovelPlaybackEngine? = nil) -> Bool {
        guard let engine = engine ?? synchronizeRuntime(), !engine.preeditBuffer.isEmpty else {
            return false
        }

        let result = engine.commitPreedit()
        do {
            let persisted = try stateStore.update { state in
                state.paragraphIndex = engine.committedParagraphIndex
                state.charIndex = engine.committedCharIndex
                state.eofReached = engine.eofReached
            }
            currentState = persisted
        } catch {
            return false
        }

        if let client = sender as? NSTextInputClient, !result.text.isEmpty {
            client.insertText(
                result.text,
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
            client.unmarkText()
        }

        return true
    }

    private func synchronizeRuntime(forceReloadDocument: Bool = false) -> NovelPlaybackEngine? {
        let persistedState = stateStore.load()
        currentState = persistedState

        guard let sourceURL = persistedState.resolvedSourceURL else {
            currentDocument = nil
            runtimeEngine = nil
            lastSourceURL = nil
            lastSourceModificationDate = nil
            return nil
        }

        do {
            let loadContext = try sourceSecurityStore.withAccessToSourceURL(
                fallback: sourceURL
            ) { securedSourceURL -> DocumentLoadContext in
                let modificationDate = try? securedSourceURL
                    .resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                let shouldReloadDocument = forceReloadDocument
                    || currentDocument == nil
                    || lastSourceURL?.path != securedSourceURL.path
                    || lastSourceModificationDate != modificationDate
                let document = shouldReloadDocument
                    ? try documentLoader.load(from: securedSourceURL)
                    : currentDocument

                return DocumentLoadContext(
                    resolvedSourceURL: securedSourceURL,
                    modificationDate: modificationDate,
                    document: document,
                    reloadedDocument: shouldReloadDocument
                )
            }

            guard let loadContext, let document = loadContext.document else {
                currentDocument = nil
                runtimeEngine = nil
                lastSourceURL = nil
                lastSourceModificationDate = nil
                return nil
            }

            currentDocument = document
            lastSourceURL = loadContext.resolvedSourceURL
            lastSourceModificationDate = loadContext.modificationDate
            if loadContext.reloadedDocument {
                runtimeEngine = nil
            }
        } catch {
            currentDocument = nil
            runtimeEngine = nil
            lastSourceURL = nil
            lastSourceModificationDate = nil
            return nil
        }

        guard let document = currentDocument else {
            return nil
        }

        let needsFreshEngine: Bool
        if let runtimeEngine {
            needsFreshEngine = runtimeEngine.committedParagraphIndex != persistedState.paragraphIndex
                || runtimeEngine.committedCharIndex != persistedState.charIndex
                || runtimeEngine.preeditBuffer.isEmpty == false && forceReloadDocument
        } else {
            needsFreshEngine = true
        }

        if needsFreshEngine {
            runtimeEngine = NovelPlaybackEngine(document: document, state: persistedState)
        }

        return runtimeEngine
    }

    private var frontmostBundleIdentifier: String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    }

    private func key(from event: NSEvent) -> NovelInputKey {
        NovelInputKey(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            command: event.modifierFlags.contains(.command),
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option)
        )
    }
}

private extension NovelInputController {
    struct DocumentLoadContext {
        let resolvedSourceURL: URL
        let modificationDate: Date?
        let document: NovelDocument?
        let reloadedDocument: Bool
    }
}
