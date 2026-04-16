import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("摸鱼助手")
                .font(.system(size: 28, weight: .bold))

            Group {
                labeledRow("安装状态", value: viewModel.installStatusText)
                labeledRow("输入法状态", value: viewModel.inputSourceStatusText)
                labeledRow("当前实际输入法", value: viewModel.currentInputSourceText)
                labeledRow("状态", value: viewModel.statusText)
                labeledRow("当前文件", value: viewModel.sourceFilePath)
                labeledRow("当前进度", value: viewModel.progressText)
                labeledRow("允许应用", value: viewModel.allowedAppsText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("首次启用指引")
                    .font(.headline)
                Text(viewModel.nextStepText)
                    .font(.body)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button("选择 txt") {
                    viewModel.chooseSourceFile()
                }

                Button(viewModel.state.armed ? "关闭 Armed" : "开启 Armed") {
                    viewModel.toggleArmed()
                }

                Button("切到摸鱼助手") {
                    viewModel.switchToMoyuAssistant()
                }

                Button("打开键盘输入法设置") {
                    viewModel.openKeyboardInputSources()
                }

                Button("查看已安装输入法") {
                    viewModel.revealInstalledInputMethod()
                }

                Button("打开输入法文件夹") {
                    viewModel.revealInputMethodsFolder()
                }

                Button("刷新") {
                    viewModel.refresh()
                }

                Button("打开诊断日志") {
                    viewModel.openDiagnosticLog()
                }

                Button("清空诊断日志") {
                    viewModel.clearDiagnosticLog()
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 420)
    }

    private func labeledRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
