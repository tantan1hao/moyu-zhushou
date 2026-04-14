from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Protocol, Sequence

from .engine import NovelTextEngine
from .platform import (
    DEFAULT_TARGET_BUNDLE_ID,
    KeyEvent,
    PermissionReport,
    PlatformAdapter,
    create_platform_adapter,
)


class ControllerContractError(RuntimeError):
    """Raised when injected dependencies do not satisfy the controller contract."""


class ControllerState(str, Enum):
    OFF = "Off"
    ARMED = "Armed"
    PAUSED = "Paused"
    EOF = "EOF"


@dataclass(frozen=True, slots=True)
class KeyResult:
    consume: bool
    text: str = ""
    backspaces: int = 0
    state: ControllerState = ControllerState.OFF
    key: str = ""


@dataclass(frozen=True, slots=True)
class InjectedChunk:
    key: str
    output: str


class EngineProtocol(Protocol):
    source_path: Path | None
    paragraph_count: int
    paragraph_index: int
    char_index: int
    current_paragraph_length: int
    progress: float

    def load_source(self, path: str | Path) -> None: ...

    def emitOnSpace(self) -> str: ...

    def emitOnReturn(self) -> str: ...

    def rewindLast(self) -> str: ...

    def hasRemainingText(self) -> bool: ...


class NovelIMEController:
    DEFAULT_ACCEPTED_BUNDLE_IDS = (
        DEFAULT_TARGET_BUNDLE_ID,
        "com.kingsoft.wpsoffice.mac",
    )

    def __init__(
        self,
        engine: EngineProtocol | None = None,
        platform: PlatformAdapter | None = None,
        *,
        target_bundle_id: str = DEFAULT_TARGET_BUNDLE_ID,
        accepted_bundle_ids: Sequence[str] | None = None,
    ) -> None:
        self.engine = engine or NovelTextEngine()
        self.platform = platform or create_platform_adapter(target_bundle_id=target_bundle_id)
        self.target_bundle_id = target_bundle_id
        self.accepted_bundle_ids = tuple(accepted_bundle_ids or self.DEFAULT_ACCEPTED_BUNDLE_IDS)

        self.enabled = False
        self.state = ControllerState.OFF
        self.frontmost_bundle_id: str | None = None
        self.permission_report = PermissionReport(
            accessibility_trusted=False,
            input_monitoring_allowed=False,
            can_post_keyboard_events=False,
            notes=("Platform hook has not been checked yet.",),
        )
        self.issue = ""
        self.hook_running = False
        self._history: list[InjectedChunk] = []

    @property
    def source_path(self) -> Path | None:
        return self.engine.source_path

    def start_hook(self) -> None:
        if self.hook_running:
            return
        self.platform.start_hook(self.process_key_event)
        self.hook_running = True

    def stop_hook(self) -> None:
        if not self.hook_running:
            return
        self.platform.stop_hook()
        self.hook_running = False

    def load_source(self, path: str | Path) -> ControllerState:
        self.engine.load_source(path)
        self._history.clear()
        return self.refresh_context_from_platform()

    def set_source_file(self, path: str | Path) -> ControllerState:
        return self.load_source(path)

    def set_enabled(self, enabled: bool) -> ControllerState:
        self.enabled = bool(enabled)
        return self._update_state()

    def toggle_enabled(self) -> ControllerState:
        return self.set_enabled(not self.enabled)

    def refresh_context_from_platform(self) -> ControllerState:
        self.frontmost_bundle_id = self.platform.get_frontmost_app()
        self.permission_report = self.platform.check_permissions()
        return self._update_state()

    def refresh(self) -> dict[str, object]:
        self.refresh_context_from_platform()
        return self.snapshot()

    def request_permissions(self) -> dict[str, object]:
        self.permission_report = self.platform.request_permissions()
        self._update_state()
        return self.snapshot()

    def handle_key(self, key: str) -> KeyResult:
        normalized = self._normalize_key(key)
        self._update_state()
        if normalized is None:
            return KeyResult(consume=False, state=self.state, key=str(key))

        if normalized == "delete":
            return self._handle_delete()

        if self.state != ControllerState.ARMED:
            return KeyResult(consume=False, state=self.state, key=normalized)

        if normalized == "space":
            emitted = self.engine.emitOnSpace()
        else:
            emitted = self.engine.emitOnReturn()

        if emitted:
            self._history.append(InjectedChunk(key=normalized, output=emitted))

        self._update_state()
        return KeyResult(
            consume=True,
            text=emitted,
            state=self.state,
            key=normalized,
        )

    def process_key_event(self, key_event: KeyEvent) -> bool:
        result = self.handle_key(key_event.key)
        if result.consume and result.backspaces:
            self.platform.inject_backspace(result.backspaces)
        if result.consume and result.text:
            self.platform.inject_text(result.text)
        return result.consume

    def snapshot(self) -> dict[str, object]:
        return {
            "status": self.state.value,
            "enabled": self.enabled,
            "current_file": str(self.source_path) if self.source_path else "",
            "progress": self.progress_text(),
            "issue": self.issue,
            "frontmost_bundle_id": self.frontmost_bundle_id,
            "accepted_bundle_ids": list(self.accepted_bundle_ids),
            "accessibility_trusted": self.permission_report.accessibility_trusted,
            "input_monitoring_allowed": self.permission_report.input_monitoring_allowed,
            "can_post_keyboard_events": self.permission_report.can_post_keyboard_events,
            "paragraph_index": self.engine.paragraph_index,
            "paragraph_count": self.engine.paragraph_count,
            "char_index": self.engine.char_index,
            "current_paragraph_length": self.engine.current_paragraph_length,
            "raw_progress": self.engine.progress,
            "hook_running": self.hook_running,
            "permissions_ready": self.permission_report.ready,
            "permission_notes": list(self.permission_report.notes),
            "history_depth": len(self._history),
        }

    def progress_text(self) -> str:
        paragraph_count = self.engine.paragraph_count
        if paragraph_count == 0:
            return "未开始"

        paragraph_number = min(self.engine.paragraph_index + 1, paragraph_count)
        current_length = self.engine.current_paragraph_length
        progress_percent = self.engine.progress * 100
        return (
            f"段 {paragraph_number}/{paragraph_count} "
            f"字 {self.engine.char_index}/{current_length} "
            f"({progress_percent:.1f}%)"
        )

    def _handle_delete(self) -> KeyResult:
        self._update_state()
        if not self._history:
            return KeyResult(consume=False, state=self.state, key="delete")

        rewound = self.engine.rewindLast()
        self._history.pop()
        backspaces = len(rewound) if rewound else 0
        self._update_state()
        return KeyResult(
            consume=backspaces > 0,
            backspaces=backspaces,
            state=self.state,
            key="delete",
        )

    def _update_state(self) -> ControllerState:
        if not self.enabled:
            self.state = ControllerState.OFF
            self.issue = ""
            return self.state

        if self.source_path is None:
            self.state = ControllerState.PAUSED
            self.issue = "请先选择 txt 源文件。"
            return self.state

        if not self.permission_report.ready:
            self.state = ControllerState.PAUSED
            self.issue = self._permission_issue()
            return self.state

        if not self.engine.hasRemainingText():
            self.state = ControllerState.EOF
            self.issue = "稿源已输出完毕。"
            return self.state

        if self.frontmost_bundle_id not in self.accepted_bundle_ids:
            self.state = ControllerState.PAUSED
            self.issue = "当前前台应用不是 Microsoft Word 或 WPS。"
            return self.state

        self.state = ControllerState.ARMED
        self.issue = ""
        return self.state

    def _permission_issue(self) -> str:
        missing = self.permission_report.missing_permissions()
        if missing:
            joined = "、".join(missing)
            return f"缺少系统权限：{joined}。"
        if self.permission_report.notes:
            return self.permission_report.notes[0]
        return "系统权限不足，无法监听或注入按键。"

    @staticmethod
    def _normalize_key(key: str) -> str | None:
        value = str(key).strip().lower()
        if value in {"space", "spacebar", " "}:
            return "space"
        if value in {"return", "enter", "newline"}:
            return "return"
        if value in {"delete", "backspace"}:
            return "delete"
        return None


NovelImeController = NovelIMEController

_CONTROLLER: NovelIMEController | None = None


def get_controller() -> NovelIMEController:
    global _CONTROLLER
    if _CONTROLLER is None:
        _CONTROLLER = NovelIMEController()
    return _CONTROLLER


def create_controller() -> NovelIMEController:
    return NovelIMEController()


__all__ = [
    "ControllerContractError",
    "ControllerState",
    "InjectedChunk",
    "KeyResult",
    "NovelIMEController",
    "NovelImeController",
    "create_controller",
    "get_controller",
]
