from __future__ import annotations

import platform
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QTimer, Qt
from PySide6.QtGui import QAction, QCursor, QIcon, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMenu,
    QMessageBox,
    QPushButton,
    QStyle,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)

from .controller import ControllerState, get_controller


APP_NAME = "Word Novel Proxy"


class TrayApp(QObject):
    def __init__(self, app: QApplication) -> None:
        super().__init__()
        self.app = app
        self.controller = get_controller()
        self._hook_error = ""
        self._last_issue = ""
        self._startup_guidance_shown = False

        self.icon = QSystemTrayIcon(self._build_icon(), self)
        self.menu = QMenu()
        self.issue_action = QAction(self.menu)
        self.panel_action = QAction("显示控制面板", self.menu)
        self.select_action = QAction("选择 txt", self.menu)
        self.permissions_action = QAction("请求权限", self.menu)
        self.toggle_action = QAction("开启模式", self.menu)
        self.status_action = QAction(self.menu)
        self.file_action = QAction(self.menu)
        self.progress_action = QAction(self.menu)
        self.exit_action = QAction("退出", self.menu)
        self.timer = QTimer(self)
        self.panel = self._build_control_panel()

        self._configure_actions()
        self._build_menu()
        self._configure_tray()
        self._configure_timer()
        self._ensure_hook_started()
        QTimer.singleShot(250, self.show_startup_guidance)

    def _build_icon(self) -> QIcon:
        style = self.app.style() if self.app else None
        if style is not None:
            icon = style.standardIcon(QStyle.StandardPixmap.SP_FileDialogDetailedView)
            if not icon.isNull():
                return icon

        pixmap = QPixmap(16, 16)
        pixmap.fill(Qt.GlobalColor.transparent)
        return QIcon(pixmap)

    def _configure_actions(self) -> None:
        self.issue_action.setVisible(False)
        self.issue_action.setEnabled(False)
        self.status_action.setEnabled(False)
        self.file_action.setEnabled(False)
        self.progress_action.setEnabled(False)
        self.panel_action.triggered.connect(self.show_control_panel)
        self.select_action.triggered.connect(self.choose_source_file)
        self.permissions_action.triggered.connect(self.request_permissions)
        self.toggle_action.triggered.connect(self.toggle_mode)
        self.exit_action.triggered.connect(self.shutdown)

    def _build_menu(self) -> None:
        self.menu.addAction(self.issue_action)
        self.menu.addSeparator()
        self.menu.addAction(self.panel_action)
        self.menu.addAction(self.select_action)
        self.menu.addAction(self.permissions_action)
        self.menu.addAction(self.toggle_action)
        self.menu.addSeparator()
        self.menu.addAction(self.status_action)
        self.menu.addAction(self.file_action)
        self.menu.addAction(self.progress_action)
        self.menu.addSeparator()
        self.menu.addAction(self.exit_action)
        self.icon.setContextMenu(self.menu)

    def _configure_tray(self) -> None:
        self.icon.setToolTip(APP_NAME)
        self.icon.activated.connect(self._on_tray_activated)
        self.icon.show()

    def _configure_timer(self) -> None:
        self.timer.setInterval(1000)
        self.timer.timeout.connect(self.refresh_state)
        self.timer.start()

    def _on_tray_activated(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.menu.popup(QCursor.pos())

    def _build_control_panel(self) -> QWidget:
        panel = QWidget()
        panel.setWindowTitle(APP_NAME)
        panel.resize(460, 220)

        layout = QVBoxLayout(panel)

        self.panel_status_label = QLabel("状态：初始化中")
        self.panel_file_label = QLabel("当前文件：未选择")
        self.panel_progress_label = QLabel("当前进度：未开始")
        self.panel_permissions_label = QLabel("权限：未知")
        self.panel_issue_label = QLabel("")
        self.panel_issue_label.setWordWrap(True)

        button_row = QHBoxLayout()
        self.panel_select_button = QPushButton("选择 txt")
        self.panel_permissions_button = QPushButton("请求权限")
        self.panel_toggle_button = QPushButton("开启模式")
        self.panel_quit_button = QPushButton("退出")

        self.panel_select_button.clicked.connect(self.choose_source_file)
        self.panel_permissions_button.clicked.connect(self.request_permissions)
        self.panel_toggle_button.clicked.connect(self.toggle_mode)
        self.panel_quit_button.clicked.connect(self.shutdown)

        button_row.addWidget(self.panel_select_button)
        button_row.addWidget(self.panel_permissions_button)
        button_row.addWidget(self.panel_toggle_button)
        button_row.addWidget(self.panel_quit_button)

        layout.addWidget(self.panel_status_label)
        layout.addWidget(self.panel_file_label)
        layout.addWidget(self.panel_progress_label)
        layout.addWidget(self.panel_permissions_label)
        layout.addWidget(self.panel_issue_label)
        layout.addStretch(1)
        layout.addLayout(button_row)

        return panel

    def show_control_panel(self) -> None:
        self.panel.show()
        self.panel.raise_()
        self.panel.activateWindow()

    def _ensure_hook_started(self) -> None:
        if self.controller.hook_running:
            return
        try:
            self.controller.start_hook()
            self._hook_error = ""
        except Exception as exc:
            self._hook_error = str(exc)

    def _issue_text(self, snapshot: dict[str, object]) -> str:
        issues: list[str] = []
        controller_issue = str(snapshot.get("issue") or "").strip()
        if controller_issue:
            issues.append(controller_issue)
        if self._hook_error:
            issues.append(self._hook_error)
        return "\n".join(dict.fromkeys(issues))

    def _tooltip(self, snapshot: dict[str, object]) -> str:
        return "\n".join(
            [
                APP_NAME,
                f"状态：{snapshot.get('status', '未知')}",
                f"当前文件：{self._humanize_path(snapshot.get('current_file'))}",
                f"当前进度：{snapshot.get('progress', '未开始')}",
            ]
        )

    @staticmethod
    def _humanize_path(path_value: object) -> str:
        text = str(path_value or "").strip()
        if not text:
            return "未选择"
        try:
            return str(Path(text).expanduser())
        except Exception:
            return text

    def refresh_state(self) -> None:
        snapshot = self.controller.refresh()
        if bool(snapshot.get("permissions_ready")) and not self.controller.hook_running:
            self._ensure_hook_started()
            snapshot = self.controller.refresh()

        issue_text = self._issue_text(snapshot)
        status = str(snapshot.get("status", "未知"))
        file_label = self._humanize_path(snapshot.get("current_file"))
        progress = str(snapshot.get("progress", "未开始"))
        permissions_text = (
            "权限："
            f"A={'Y' if snapshot.get('accessibility_trusted') else 'N'} "
            f"IM={'Y' if snapshot.get('input_monitoring_allowed') else 'N'} "
            f"Post={'Y' if snapshot.get('can_post_keyboard_events') else 'N'}"
        )

        self.status_action.setText(f"状态：{status}")
        self.file_action.setText(f"当前文件：{file_label}")
        self.progress_action.setText(f"当前进度：{progress}")
        self.toggle_action.setText("关闭模式" if self.controller.enabled else "开启模式")
        self.panel_status_label.setText(f"状态：{status}")
        self.panel_file_label.setText(f"当前文件：{file_label}")
        self.panel_progress_label.setText(f"当前进度：{progress}")
        self.panel_permissions_label.setText(permissions_text)
        self.panel_toggle_button.setText("关闭模式" if self.controller.enabled else "开启模式")

        if issue_text:
            self.issue_action.setText(f"提示：{issue_text.splitlines()[0]}")
            self.issue_action.setVisible(True)
            self.panel_issue_label.setText(f"提示：{issue_text}")
        else:
            self.issue_action.setVisible(False)
            self.panel_issue_label.setText("提示：无")

        self.icon.setToolTip(self._tooltip(snapshot))
        if issue_text and issue_text != self._last_issue:
            self._last_issue = issue_text
            self.icon.showMessage(APP_NAME, issue_text, QSystemTrayIcon.MessageIcon.Warning, 5000)
        elif not issue_text:
            self._last_issue = ""

    def show_startup_guidance(self) -> None:
        if self._startup_guidance_shown:
            return

        self._startup_guidance_shown = True
        snapshot = self.controller.refresh()
        issue_text = self._issue_text(snapshot)

        lines = [
            "程序已经启动。",
            "我已经同时打开控制面板窗口。",
            "如果没看到菜单栏图标，直接用这个窗口继续即可。",
        ]
        if issue_text:
            lines.append(f"当前提示：{issue_text}")
        if self.controller.source_path is None:
            lines.append("现在会帮你打开 txt 选择框。")

        QMessageBox.information(None, APP_NAME, "\n".join(lines))
        self.show_control_panel()

        if self.controller.source_path is None:
            self.choose_source_file()

    def choose_source_file(self) -> None:
        file_path, _ = QFileDialog.getOpenFileName(
            None,
            "选择 txt 源文件",
            str(Path.home()),
            "Text files (*.txt);;All files (*)",
        )
        if not file_path:
            return

        try:
            self.controller.set_source_file(file_path)
        except Exception as exc:
            QMessageBox.critical(None, APP_NAME, f"选择源文件失败：{exc}")
            return

        self.refresh_state()
        self.icon.showMessage(
            APP_NAME,
            f"已选择源文件：{self._humanize_path(file_path)}",
            QSystemTrayIcon.MessageIcon.Information,
            3000,
        )
        self.show_control_panel()

    def toggle_mode(self) -> None:
        if not self.controller.enabled and self.controller.source_path is None:
            QMessageBox.warning(None, APP_NAME, "请先选择 txt 源文件。")
            return

        was_enabled = self.controller.enabled
        self._ensure_hook_started()
        self.controller.toggle_enabled()
        self.refresh_state()

        if self.controller.state == ControllerState.ARMED:
            message = "模式已开启：仅在 Microsoft Word 前台时接管 Space / Return / Delete。"
        elif self.controller.state == ControllerState.OFF:
            message = "模式已关闭。"
        elif not was_enabled and self.controller.enabled:
            message = "模式已开启。当前前台是控制面板窗口，切回 WPS 或 Word 后会自动进入 Armed。"
            self.panel.hide()
        else:
            message = str(self.controller.issue or f"当前状态：{self.controller.state.value}")

        self.icon.showMessage(APP_NAME, message, QSystemTrayIcon.MessageIcon.Information, 3500)
        if self.controller.enabled:
            return
        self.show_control_panel()

    def request_permissions(self) -> None:
        snapshot = self.controller.request_permissions()
        self.refresh_state()
        self.show_control_panel()

        if snapshot.get("permissions_ready"):
            message = "权限已经就绪。"
        else:
            message = "已触发权限请求。请在系统弹窗或系统设置里确认 Python 权限，然后重新点击这个按钮或重启程序。"

        QMessageBox.information(None, APP_NAME, message)

    def shutdown(self) -> None:
        try:
            self.controller.stop_hook()
        finally:
            self.icon.hide()
            self.app.quit()


def _startup_blockers() -> list[str]:
    blockers: list[str] = []
    if platform.system() != "Darwin":
        blockers.append("当前平台不是 macOS，菜单栏原型只支持 macOS。")
    return blockers


def run_app() -> int:
    blockers = _startup_blockers()
    if blockers:
        print("\n".join(blockers), file=sys.stderr)
        return 1

    app = QApplication.instance() or QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName(APP_NAME)
    app.setOrganizationName("novel_ime")

    if not QSystemTrayIcon.isSystemTrayAvailable():
        QMessageBox.critical(None, APP_NAME, "系统托盘不可用，无法启动菜单栏应用。")
        return 1

    tray = TrayApp(app)
    app.aboutToQuit.connect(tray.controller.stop_hook)
    app.aboutToQuit.connect(tray.icon.hide)
    tray.refresh_state()
    tray.show_control_panel()
    return app.exec()


__all__ = ["TrayApp", "run_app"]
