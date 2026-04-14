from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from novel_ime.controller import ControllerState, NovelIMEController
from novel_ime.platform import KeyEvent, PermissionReport


class FakePlatform:
    def __init__(self) -> None:
        self.frontmost_app = "com.microsoft.Word"
        self.permission_report = PermissionReport(
            accessibility_trusted=True,
            input_monitoring_allowed=True,
            can_post_keyboard_events=True,
        )
        self.injected_text: list[str] = []
        self.injected_backspaces: list[int] = []
        self.handler = None
        self.hook_started = False

    def start_hook(self, handler=None) -> None:
        self.handler = handler
        self.hook_started = True

    def stop_hook(self) -> None:
        self.hook_started = False

    def get_frontmost_app(self) -> str | None:
        return self.frontmost_app

    def inject_text(self, text: str) -> None:
        self.injected_text.append(text)

    def inject_backspace(self, count: int = 1) -> None:
        self.injected_backspaces.append(count)

    def check_permissions(self) -> PermissionReport:
        return self.permission_report


class NovelIMEControllerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.source_path = Path(self.temp_dir.name) / "sample.txt"
        self.source_path.write_text("AB\n\nCD", encoding="utf-8")
        self.platform = FakePlatform()
        self.controller = NovelIMEController(platform=self.platform)
        self.controller.load_source(self.source_path)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_refresh_enters_armed_when_enabled_word_frontmost_and_permissions_ready(self) -> None:
        self.controller.set_enabled(True)
        state = self.controller.refresh_context_from_platform()

        self.assertEqual(state, ControllerState.ARMED)
        self.assertEqual(self.controller.state, ControllerState.ARMED)
        self.assertEqual(self.controller.issue, "")

    def test_refresh_pauses_when_word_is_not_frontmost(self) -> None:
        self.controller.set_enabled(True)
        self.platform.frontmost_app = "com.apple.TextEdit"

        state = self.controller.refresh_context_from_platform()

        self.assertEqual(state, ControllerState.PAUSED)
        self.assertIn("Microsoft Word", self.controller.issue)

    def test_refresh_enters_armed_when_wps_is_frontmost(self) -> None:
        self.controller.set_enabled(True)
        self.platform.frontmost_app = "com.kingsoft.wpsoffice.mac"

        state = self.controller.refresh_context_from_platform()

        self.assertEqual(state, ControllerState.ARMED)
        self.assertEqual(self.controller.state, ControllerState.ARMED)

    def test_refresh_pauses_when_permissions_are_missing(self) -> None:
        self.controller.set_enabled(True)
        self.platform.permission_report = PermissionReport(
            accessibility_trusted=False,
            input_monitoring_allowed=True,
            can_post_keyboard_events=True,
        )

        state = self.controller.refresh_context_from_platform()

        self.assertEqual(state, ControllerState.PAUSED)
        self.assertIn("Accessibility", self.controller.issue)

    def test_process_key_event_injects_text_and_backspace(self) -> None:
        self.controller.set_enabled(True)
        self.controller.refresh_context_from_platform()

        self.assertTrue(self.controller.process_key_event(KeyEvent(key="space")))
        self.assertEqual(self.platform.injected_text, ["A"])
        self.assertEqual(self.controller.state, ControllerState.ARMED)

        self.assertTrue(self.controller.process_key_event(KeyEvent(key="return")))
        self.assertEqual(self.platform.injected_text[-1], "\n")
        self.assertEqual(self.controller.engine.paragraph_index, 1)
        self.assertEqual(self.controller.engine.char_index, 0)

        self.assertTrue(self.controller.process_key_event(KeyEvent(key="delete")))
        self.assertEqual(self.platform.injected_backspaces, [1])
        self.assertEqual(self.controller.engine.paragraph_index, 0)
        self.assertEqual(self.controller.engine.char_index, 1)

    def test_delete_without_history_passes_through(self) -> None:
        self.controller.set_enabled(True)
        self.controller.refresh_context_from_platform()

        result = self.controller.handle_key("delete")

        self.assertFalse(result.consume)
        self.assertEqual(result.backspaces, 0)


if __name__ == "__main__":
    unittest.main()
