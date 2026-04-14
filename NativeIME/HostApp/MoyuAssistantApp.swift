import SwiftUI

@main
struct MoyuAssistantApp: App {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 560, height: 360)
    }
}
