import AppKit
import Carbon
import InputMethodKit
import NovelIMECore
import SwiftUI

@MainActor
final class MoyuManualApplication: NSApplication {
    private let manualDelegate = MoyuAssistantAppDelegate()

    override init() {
        super.init()
        delegate = manualDelegate
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@main
@MainActor
final class MoyuAssistantAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var server: IMKServer?
    private lazy var viewModel = SettingsViewModel()
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--register-input-source") {
            let result = InputSourceRegistrar.registerFromCurrentBundle(
                enable: true,
                select: arguments.contains("--select-input-source")
            )
            for message in result.messages {
                print(message)
            }
            for status in result.enableStatuses {
                print("enable=\(status)")
            }
            if let selectStatus = result.selectStatus {
                print("select=\(selectStatus)")
            }
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
            ?? NovelIMEConstants.connectionName
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

        if arguments.contains("--show-settings") {
            showSettingsWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if settingsWindowController?.window?.isVisible != true {
            showSettingsWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    private func showSettingsWindow() {
        viewModel.refresh()

        elevateProcessForSettingsWindow()

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        if settingsWindowController == nil {
            let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
            let window = NSWindow(contentViewController: hostingController)
            window.title = NovelIMEConstants.appName
            window.setContentSize(NSSize(width: 560, height: 360))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.delegate = self
            settingsWindowController = NSWindowController(window: window)
        }

        guard let window = settingsWindowController?.window else {
            return
        }

        window.center()
        settingsWindowController?.showWindow(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func elevateProcessForSettingsWindow() {
        var processSerialNumber = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&processSerialNumber, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
    }

    func windowWillClose(_ notification: Notification) {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
