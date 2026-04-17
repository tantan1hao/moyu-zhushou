import AppKit
import InputMethodKit
import NovelIMECore

@objc(MoyuIMEExtensionDelegate)
final class MoyuIMEExtensionDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
            ?? NovelIMEConstants.connectionName
        NovelDiagnosticLogger.log("ime", "applicationDidFinishLaunching connection=\(connectionName)")
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        NovelDiagnosticLogger.log("ime", "IMKServer created bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
    }
}
