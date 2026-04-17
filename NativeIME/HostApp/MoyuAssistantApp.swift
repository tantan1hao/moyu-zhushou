import Foundation
import InputMethodKit
import SwiftUI
import NovelIMECore

@main
struct MoyuAssistantApp: App {
    @StateObject private var viewModel: SettingsViewModel
    private let server: IMKServer?

    init() {
        let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        if let exitCode = CommandLineAction.runIfNeeded(arguments: arguments) {
            exit(exitCode)
        }

        NovelDiagnosticLogger.log("host", "application init")
        let connectionName = NovelIMEConstants.connectionName
        server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        let serverCreated = server != nil
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "nil"
        NovelDiagnosticLogger.log(
            "host",
            "IMKServer created connection=\(connectionName) bundle=\(bundleIdentifier) server=\(serverCreated)"
        )
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    var body: some Scene {
        WindowGroup {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 560, height: 360)
    }
}

private enum CommandLineAction {
    static func runIfNeeded(arguments: [String]) -> Int32? {
        guard arguments.isEmpty == false else {
            return nil
        }

        let bundleURL = Bundle.main.bundleURL
        let joinedArguments = arguments.joined(separator: " ")
        NovelDiagnosticLogger.log("host", "command arguments=\(joinedArguments)")

        switch arguments[0] {
        case "--register-input-source":
            return InputSourceRegistrar.registerInputSource(at: bundleURL) == noErr ? 0 : 1
        case "--enable-input-source":
            return InputSourceRegistrar.enableInputMode() == noErr ? 0 : 1
        case "--select-input-source":
            return InputSourceRegistrar.selectInputMode() == noErr ? 0 : 1
        case "--verify-input-source":
            return InputSourceRegistrar.verifySelection() ? 0 : 1
        case "--print-current-input-source":
            if let descriptor = InputSourceRegistrar.currentSelectedInputSource() {
                print("\(descriptor.localizedName)|\(descriptor.inputSourceID)|\(descriptor.bundleIdentifier)|selectCapable=\(descriptor.selectCapable)")
                return 0
            }
            return 1
        case "--print-selected-input-sources":
            for entry in InputSourceRegistrar.appleSelectedInputSources() {
                print(entry)
            }
            return 0
        default:
            return nil
        }
    }
}
