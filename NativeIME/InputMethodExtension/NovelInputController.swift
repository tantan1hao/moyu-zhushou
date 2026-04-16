import AppKit
import InputMethodKit
import NovelIMECore
import OSLog

@objc(NovelInputController)
final class NovelInputController: IMKInputController {
    private let stateStore = NovelIMEStateStore()
    private let sourceSecurityStore = NovelSourceSecurityStore()
    private let documentLoader = NovelDocumentLoader()
    private let inputPolicy = NovelInputPolicy()
    private let logger = Logger(subsystem: NovelIMEConstants.hostBundleIdentifier, category: "input")

    private var currentClient: AnyObject?
    private var currentState: NovelIMEPersistedState = .default
    private var currentDocument: NovelDocument?
    private var runtimeEngine: NovelPlaybackEngine?
    private var lastSourceURL: URL?
    private var lastSourceModificationDate: Date?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        let clientType = inputClient.map { String(describing: type(of: $0)) } ?? "nil"
        NovelDiagnosticLogger.log("init clientType=\(clientType)", category: "ime")
    }

    override func activateServer(_ sender: Any!) {
        NovelDiagnosticLogger.log("activateServer frontmost=\(frontmostBundleIdentifier)", category: "ime")
        _ = synchronizeRuntime(forceReloadDocument: true)
    }

    override func deactivateServer(_ sender: Any!) {
        NovelDiagnosticLogger.log("deactivateServer", category: "ime")
        runtimeEngine?.clearPreedit()
        pushComposition(sender)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else {
            return false
        }

        return handleInput(
            sender,
            key: key(from: event),
            logPrefix: "handle keyDown chars=\(event.charactersIgnoringModifiers ?? "-") keyCode=\(event.keyCode)"
        )
    }

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        guard let string, !string.isEmpty else {
            return false
        }

        return handleInput(
            sender,
            key: NovelInputKey(
                charactersIgnoringModifiers: string,
                keyCode: 0,
                command: false,
                control: false,
                option: false
            ),
            logPrefix: "inputText string=\(string)"
        )
    }

    override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        guard let string, !string.isEmpty else {
            return false
        }

        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(flags))
        return handleInput(
            sender,
            key: NovelInputKey(
                charactersIgnoringModifiers: string,
                keyCode: UInt16(truncatingIfNeeded: keyCode),
                command: modifierFlags.contains(.command),
                control: modifierFlags.contains(.control),
                option: modifierFlags.contains(.option)
            ),
            logPrefix: "inputText:key string=\(string) keyCode=\(keyCode) modifiers=\(flags)"
        )
    }

    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        rememberClient(sender)

        guard let engine = synchronizeRuntime() else {
            return false
        }

        let selectorName = NSStringFromSelector(aSelector)
        NovelDiagnosticLogger.log("didCommand selector=\(selectorName)", category: "ime")
        logger.notice(
            "didCommand selector=\(selectorName, privacy: .public) armed=\(self.currentState.armed, privacy: .public) frontmost=\(self.frontmostBundleIdentifier, privacy: .public)"
        )
        NSLog("[MoyuAssistant] didCommand selector=%@", selectorName)

        switch selectorName {
        case "deleteBackward:":
            return handleDelete(sender, engine: engine)
        case "insertNewline:", "insertLineBreak:":
            return handleReturn(sender, engine: engine)
        default:
            return false
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

    private func handleDelete(_ sender: Any!, engine: NovelPlaybackEngine) -> Bool {
        guard !engine.preeditBuffer.isEmpty else {
            return false
        }

        _ = engine.rewindPreedit()
        pushComposition(sender)
        return true
    }

    private func handleReturn(_ sender: Any!, engine: NovelPlaybackEngine) -> Bool {
        commitCurrentPreedit(sender, engine: engine)
    }

    private func handleInput(_ sender: Any!, key: NovelInputKey, logPrefix: String) -> Bool {
        rememberClient(sender)

        guard let engine = synchronizeRuntime() else {
            return false
        }

        let action = inputPolicy.action(
            for: key,
            context: NovelInputContext(
                armed: currentState.armed,
                frontmostBundleID: frontmostBundleIdentifier,
                allowedBundleIDs: currentState.allowedBundleIDs,
                hasRemainingText: engine.hasRemainingText,
                hasPreedit: !engine.preeditBuffer.isEmpty
            )
        )

        logger.notice(
            "\(logPrefix, privacy: .public) action=\(String(describing: action), privacy: .public) armed=\(self.currentState.armed, privacy: .public) frontmost=\(self.frontmostBundleIdentifier, privacy: .public)"
        )
        NSLog("[MoyuAssistant] %@ action=%@ armed=%d frontmost=%@", logPrefix, String(describing: action), currentState.armed, frontmostBundleIdentifier)
        NovelDiagnosticLogger.log("\(logPrefix) action=\(String(describing: action)) armed=\(currentState.armed) frontmost=\(frontmostBundleIdentifier)", category: "ime")

        switch action {
        case .passThrough:
            return false
        case .rewindPreedit:
            return handleDelete(sender, engine: engine)
        case .commitPreedit:
            return handleReturn(sender, engine: engine)
        case .advancePreedit:
            if !engine.hasRemainingText && engine.preeditBuffer.isEmpty {
                return false
            }

            _ = engine.appendNextCharacter()
            pushComposition(sender)
            return true
        }
    }

    @discardableResult
    private func commitCurrentPreedit(_ sender: Any!, engine: NovelPlaybackEngine? = nil) -> Bool {
        guard let engine = engine ?? synchronizeRuntime(), !engine.preeditBuffer.isEmpty else {
            NovelDiagnosticLogger.log("commitCurrentPreedit skipped empty-buffer", category: "ime")
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
            NovelDiagnosticLogger.log("commitCurrentPreedit state update failed", category: "ime")
            return false
        }

        if !result.text.isEmpty {
            NovelDiagnosticLogger.log("commitCurrentPreedit text=\(result.text)", category: "ime")
            if let client = resolvedClient(from: sender) {
                let inserted = invokeInsertText(
                    on: client,
                    text: result.text,
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
                let unmarked = invokeUnmarkText(on: client)
                NovelDiagnosticLogger.log(
                    "commitCurrentPreedit delivered inserted=\(inserted) unmarked=\(unmarked) clientType=\(String(describing: type(of: client)))",
                    category: "ime"
                )
            } else {
                NovelDiagnosticLogger.log("commitCurrentPreedit no client for text delivery", category: "ime")
            }
        }

        pushComposition(sender)
        return true
    }

    private func synchronizeRuntime(forceReloadDocument: Bool = false) -> NovelPlaybackEngine? {
        let persistedState = stateStore.load()
        currentState = persistedState

        guard let sourceURL = persistedState.resolvedSourceURL else {
            NovelDiagnosticLogger.log("synchronizeRuntime no sourceURL armed=\(persistedState.armed)", category: "ime")
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
                NovelDiagnosticLogger.log("synchronizeRuntime loadContext missing path=\(sourceURL.path)", category: "ime")
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
                NovelDiagnosticLogger.log("synchronizeRuntime reloaded path=\(loadContext.resolvedSourceURL.path)", category: "ime")
                runtimeEngine = nil
            }
        } catch {
            NovelDiagnosticLogger.log("synchronizeRuntime failed path=\(sourceURL.path) error=\(error.localizedDescription)", category: "ime")
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
            NovelDiagnosticLogger.log(
                "runtimeEngine created paragraph=\(persistedState.paragraphIndex) char=\(persistedState.charIndex) eof=\(persistedState.eofReached)",
                category: "ime"
            )
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

    private func pushComposition(_ sender: Any! = nil) {
        let client = resolvedClient(from: sender)

        guard let engine = runtimeEngine, !engine.preeditBuffer.isEmpty else {
            if let client {
                let unmarked = invokeUnmarkText(on: client)
                NovelDiagnosticLogger.log(
                    "pushComposition clearing marked text unmarked=\(unmarked) clientType=\(String(describing: type(of: client)))",
                    category: "ime"
                )
            } else {
                NovelDiagnosticLogger.log("pushComposition clearing marked text without resolved client", category: "ime")
            }
            return
        }

        let markedText = NSAttributedString(
            string: engine.preeditBuffer,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        let caretPosition = engine.preeditBuffer.utf16.count
        if let client {
            let clientTypeDescription = String(describing: type(of: client))
            logger.notice("setMarkedText preedit=\(engine.preeditBuffer, privacy: .public) caret=\(caretPosition)")
            NSLog("[MoyuAssistant] setMarkedText preedit=%@ caret=%ld", engine.preeditBuffer, caretPosition)
            NovelDiagnosticLogger.log(
                "pushComposition direct setMarkedText begin preedit=\(engine.preeditBuffer) caret=\(caretPosition) clientType=\(clientTypeDescription)",
                category: "ime"
            )
            let marked = invokeSetMarkedText(
                on: client,
                markedText: markedText,
                selectedRange: NSRange(location: caretPosition, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
            NovelDiagnosticLogger.log(
                "pushComposition direct setMarkedText success=\(marked) preedit=\(engine.preeditBuffer) caret=\(caretPosition) clientType=\(String(describing: type(of: client)))",
                category: "ime"
            )
        } else {
            NovelDiagnosticLogger.log("pushComposition no resolved client for direct setMarkedText", category: "ime")
        }
    }

    private func rememberClient(_ sender: Any!) {
        if let sender = sender as AnyObject? {
            currentClient = sender
        }
    }

    private func resolvedClient(from sender: Any! = nil) -> AnyObject? {
        rememberClient(sender)

        if let currentClient {
            return currentClient
        }

        if let controllerClient = self.client() as AnyObject? {
            currentClient = controllerClient
            NovelDiagnosticLogger.log(
                "resolvedClient from controller clientType=\(String(describing: type(of: controllerClient)))",
                category: "ime"
            )
            return controllerClient
        }

        let senderType = sender.map { String(describing: type(of: $0)) } ?? "nil"
        NovelDiagnosticLogger.log("resolvedClient unavailable senderType=\(senderType)", category: "ime")
        return nil
    }

    private func invokeSetMarkedText(
        on client: AnyObject,
        markedText: NSAttributedString,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) -> Bool {
        let selector = NovelInputControllerSelectors.setMarkedText
        guard client.responds(to: selector) else {
            return false
        }

        let implementation = client.method(for: selector)
        let function = unsafeBitCast(implementation, to: SetMarkedTextIMP.self)
        function(client, selector, markedText, selectedRange, replacementRange)
        return true
    }

    private func invokeInsertText(on client: AnyObject, text: String, replacementRange: NSRange) -> Bool {
        let selector = NovelInputControllerSelectors.insertText
        guard client.responds(to: selector) else {
            return false
        }

        let implementation = client.method(for: selector)
        let function = unsafeBitCast(implementation, to: InsertTextIMP.self)
        function(client, selector, text, replacementRange)
        return true
    }

    private func invokeUnmarkText(on client: AnyObject) -> Bool {
        let selector = NovelInputControllerSelectors.unmarkText
        guard client.responds(to: selector) else {
            return false
        }

        let implementation = client.method(for: selector)
        let function = unsafeBitCast(implementation, to: UnmarkTextIMP.self)
        function(client, selector)
        return true
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

private enum NovelInputControllerSelectors {
    static let setMarkedText = NSSelectorFromString("setMarkedText:selectedRange:replacementRange:")
    static let insertText = NSSelectorFromString("insertText:replacementRange:")
    static let unmarkText = NSSelectorFromString("unmarkText")
}

private typealias SetMarkedTextIMP = @convention(c) (AnyObject, Selector, Any, NSRange, NSRange) -> Void
private typealias InsertTextIMP = @convention(c) (AnyObject, Selector, Any, NSRange) -> Void
private typealias UnmarkTextIMP = @convention(c) (AnyObject, Selector) -> Void
