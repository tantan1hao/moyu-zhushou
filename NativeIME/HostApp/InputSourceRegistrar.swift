import Carbon
import Foundation
import NovelIMECore

enum InputSourceRegistrar {
    struct Result {
        let messages: [String]
        let registerStatus: OSStatus
        let enableStatuses: [String]
        let selectStatus: String?
    }

    static func registerFromCurrentBundle(enable: Bool = true, select: Bool = false) -> Result {
        var messages: [String] = []
        var enableStatuses: [String] = []
        var selectStatus: String?

        let bundleURL = Bundle.main.bundleURL as CFURL
        let registerStatus = TISRegisterInputSource(bundleURL)
        messages.append("TISRegisterInputSource=\(registerStatus)")

        let filter = [kTISPropertyBundleID as String: NovelIMEConstants.hostBundleIdentifier] as CFDictionary
        let sourceList = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray

        var selectedSource: TISInputSource?

        for item in sourceList {
            let source = unsafeBitCast(item, to: TISInputSource.self)
            let sourceID = stringProperty(for: source, key: kTISPropertyInputSourceID)
            let enableCapable = boolProperty(for: source, key: kTISPropertyInputSourceIsEnableCapable)
            let selectCapable = boolProperty(for: source, key: kTISPropertyInputSourceIsSelectCapable)

            messages.append("source=\(sourceID) enableCapable=\(enableCapable) selectCapable=\(selectCapable)")

            if enable, enableCapable {
                let status = TISEnableInputSource(source)
                enableStatuses.append("\(sourceID)=\(status)")
            }

            if sourceID == NovelIMEConstants.inputModeIdentifier || sourceID == NovelIMEConstants.inputSourceIdentifier {
                selectedSource = source
            }
        }

        if select, let selectedSource, boolProperty(for: selectedSource, key: kTISPropertyInputSourceIsSelectCapable) {
            let sourceID = stringProperty(for: selectedSource, key: kTISPropertyInputSourceID)
            let status = TISSelectInputSource(selectedSource)
            selectStatus = "\(sourceID)=\(status)"
        }

        return Result(
            messages: messages,
            registerStatus: registerStatus,
            enableStatuses: enableStatuses,
            selectStatus: selectStatus
        )
    }

    private static func stringProperty(for source: TISInputSource, key: CFString) -> String {
        guard let value = cfObjectProperty(for: source, key: key) else {
            return ""
        }
        return value as? String ?? ""
    }

    private static func boolProperty(for source: TISInputSource, key: CFString) -> Bool {
        guard let value = cfObjectProperty(for: source, key: key) else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private static func cfObjectProperty(for source: TISInputSource, key: CFString) -> AnyObject? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
    }
}
