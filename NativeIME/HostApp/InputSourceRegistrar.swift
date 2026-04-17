import AppKit
import Carbon
import NovelIMECore

struct InputSourceDescriptor: Equatable {
    let localizedName: String
    let inputSourceID: String
    let bundleIdentifier: String
    let selectCapable: Bool
}

enum InputSourceRegistrar {
    static func registerInputSource(at appURL: URL) -> OSStatus {
        NovelDiagnosticLogger.log("registrar", "register appURL=\(appURL.path)")
        return TISRegisterInputSource(appURL as CFURL)
    }

    static func enableInputMode() -> OSStatus? {
        guard let source = inputModeSource() else {
            NovelDiagnosticLogger.log("registrar", "enable missing input mode")
            return nil
        }

        let status = TISEnableInputSource(source)
        NovelDiagnosticLogger.log("registrar", "enable status=\(status)")
        return status
    }

    static func selectInputMode() -> OSStatus? {
        guard let source = inputModeSource() else {
            NovelDiagnosticLogger.log("registrar", "select missing input mode")
            return nil
        }

        let status = TISSelectInputSource(source)
        NovelDiagnosticLogger.log("registrar", "select status=\(status)")
        return status
    }

    static func currentSelectedInputSource() -> InputSourceDescriptor? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            NovelDiagnosticLogger.log("registrar", "currentSelectedInputSource missing current source")
            return nil
        }

        let descriptor = descriptor(for: source)
        NovelDiagnosticLogger.log(
            "registrar",
            "currentSelectedInputSource \(descriptor.localizedName) (\(descriptor.inputSourceID) / \(descriptor.bundleIdentifier)) selected=\(descriptor.selectCapable)"
        )
        return descriptor
    }

    static func appleSelectedInputSources() -> [[String: Any]] {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.HIToolbox")
        return domain?["AppleSelectedInputSources"] as? [[String: Any]] ?? []
    }

    static func appleSelectedIncludesModeIdentifier() -> Bool {
        let entries = appleSelectedInputSources()
        let includesMode = entries.contains { entry in
            (entry["InputSourceID"] as? String) == NovelIMEConstants.inputModeIdentifier
                || (entry["KeyboardLayout ID"] as? String) == NovelIMEConstants.inputModeIdentifier
        }
        NovelDiagnosticLogger.log("registrar", "appleSelectedIncludesModeIdentifier=\(includesMode)")
        return includesMode
    }

    static func verifySelection() -> Bool {
        let currentMatches = currentSelectedInputSource()?.inputSourceID == NovelIMEConstants.inputModeIdentifier
        let selectedMatches = appleSelectedIncludesModeIdentifier()
        let verified = currentMatches && selectedMatches
        NovelDiagnosticLogger.log(
            "registrar",
            "verifySelection currentMatches=\(currentMatches) selectedMatches=\(selectedMatches) verified=\(verified)"
        )
        return verified
    }

    private static func inputModeSource() -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: NovelIMEConstants.inputModeIdentifier] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        return sources.first(where: { descriptor(for: $0).selectCapable }) ?? sources.first
    }

    private static func descriptor(for source: TISInputSource) -> InputSourceDescriptor {
        let localizedName = propertyValue(kTISPropertyLocalizedName, from: source) as? String ?? "Unknown"
        let inputSourceID = propertyValue(kTISPropertyInputSourceID, from: source) as? String ?? ""
        let bundleIdentifier = propertyValue(kTISPropertyBundleID, from: source) as? String ?? ""
        let selectCapable = (propertyValue(kTISPropertyInputSourceIsSelectCapable, from: source) as? Bool) ?? false

        return InputSourceDescriptor(
            localizedName: localizedName,
            inputSourceID: inputSourceID,
            bundleIdentifier: bundleIdentifier,
            selectCapable: selectCapable
        )
    }

    private static func propertyValue(_ key: CFString, from source: TISInputSource) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
