import AppKit
import InputMethodKit
import NovelIMECore

@objc(MoyuNovelInputController)
final class NovelInputController: IMKInputController {
    private let stateStore = NovelIMEStateStore()
    private let documentLoader = NovelDocumentLoader()
    private let inputPolicy = NovelInputPolicy()

    private var currentState: NovelIMEPersistedState = .default
    private var currentDocument: NovelDocument?
    private var runtimeEngine: NovelPlaybackEngine?
    private var lastSourceURL: URL?

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
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, _ in }
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
        let persisted = engine.persistedState(from: currentState)
        do {
            try stateStore.save(persisted)
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
            return nil
        }

        if forceReloadDocument || currentDocument == nil || lastSourceURL != sourceURL {
            do {
                currentDocument = try documentLoader.load(from: sourceURL)
                lastSourceURL = sourceURL
                runtimeEngine = nil
            } catch {
                currentDocument = nil
                runtimeEngine = nil
                return nil
            }
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
