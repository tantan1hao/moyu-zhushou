import AppKit
import InputMethodKit
import NovelIMECore

@objc(MoyuIMEExtensionDelegate)
final class MoyuIMEExtensionDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
            ?? NovelIMEConstants.connectionName
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
    }
}
