"""macOS platform adapter built on PyObjC and Quartz."""

from __future__ import annotations

import ctypes
import threading
from typing import Callable

from .base import (
    KeyEvent,
    PermissionReport,
    PlatformAdapter,
    PlatformError,
    normalize_bundle_id,
)

PYOBJC_AVAILABLE = False
PYOBJC_IMPORT_ERROR: Exception | None = None

try:  # pragma: no cover - exercised only on macOS with PyObjC installed.
    import AppKit  # type: ignore
    import Foundation  # type: ignore
    import Quartz  # type: ignore
    import objc  # type: ignore

    PYOBJC_AVAILABLE = True
except Exception as exc:  # pragma: no cover - import fallback is the point.
    AppKit = None  # type: ignore[assignment]
    Foundation = None  # type: ignore[assignment]
    Quartz = None  # type: ignore[assignment]
    objc = None  # type: ignore[assignment]
    PYOBJC_IMPORT_ERROR = exc


DEFAULT_TARGET_BUNDLE_ID = "com.microsoft.Word"

_SPACE_KEYCODE = 49
_RETURN_KEYCODE = 36
_KEYPAD_RETURN_KEYCODE = 76
_DELETE_KEYCODE = 51
_APPLICATION_SERVICES_PATH = (
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
)


class MacOSPlatformAdapter(PlatformAdapter):
    """macOS implementation using a global Quartz keydown tap."""

    def __init__(self, target_bundle_id: str = DEFAULT_TARGET_BUNDLE_ID) -> None:
        self.target_bundle_id = target_bundle_id
        self._handler: Callable[[KeyEvent], bool | None] | None = None
        self._hook_thread: threading.Thread | None = None
        self._hook_ready = threading.Event()
        self._hook_stop = threading.Event()
        self._hook_error: Exception | None = None
        self._lock = threading.RLock()
        self._tap = None
        self._run_loop = None
        self._run_loop_source = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def start_hook(
        self, handler: Callable[[KeyEvent], bool | None] | None = None
    ) -> None:
        self._ensure_available()
        self._validate_permissions_for_hook()

        with self._lock:
            self._handler = handler or self._handler or (lambda event: True)
            if self._hook_thread and self._hook_thread.is_alive():
                return

            self._hook_stop.clear()
            self._hook_ready.clear()
            self._hook_error = None

            thread = threading.Thread(
                target=self._run_hook_loop,
                name="novel-ime-macos-event-tap",
                daemon=True,
            )
            self._hook_thread = thread
            thread.start()

        if not self._hook_ready.wait(timeout=3.0):
            self.stop_hook()
            raise PlatformError(
                "macOS key hook failed to start: "
                f"{self._hook_error or 'timed out waiting for the event tap to initialize'}"
            )

        if self._hook_error is not None:
            error = self._hook_error
            self.stop_hook()
            raise PlatformError(f"macOS key hook failed to start: {error}") from error

    def stop_hook(self) -> None:
        with self._lock:
            self._hook_stop.set()

            if self._tap is not None and PYOBJC_AVAILABLE:
                try:
                    Quartz.CGEventTapEnable(self._tap, False)
                except Exception:
                    pass

            if self._run_loop is not None and PYOBJC_AVAILABLE:
                try:
                    Quartz.CFRunLoopStop(self._run_loop)
                except Exception:
                    pass

            thread = self._hook_thread

        if thread and thread.is_alive():
            thread.join(timeout=2.0)

        with self._lock:
            self._hook_thread = None
            self._hook_error = None
            self._handler = None
            self._tap = None
            self._run_loop = None
            self._run_loop_source = None
            self._hook_ready.clear()

    def get_frontmost_app(self) -> str | None:
        self._ensure_available()

        workspace = AppKit.NSWorkspace.sharedWorkspace()
        app = workspace.frontmostApplication()
        if app is None:
            return None

        bundle_id = app.bundleIdentifier()
        return normalize_bundle_id(bundle_id)

    def inject_text(self, text: str) -> None:
        self._ensure_available()
        if not text:
            return

        for char in text:
            if char in {"\n", "\r"}:
                self._post_keycode(_RETURN_KEYCODE)
                continue
            self._post_unicode_character(char)

    def inject_backspace(self, count: int = 1) -> None:
        self._ensure_available()
        if count <= 0:
            return

        for _ in range(count):
            self._post_keycode(_DELETE_KEYCODE)

    def check_permissions(self) -> PermissionReport:
        if not PYOBJC_AVAILABLE:
            return PermissionReport(
                accessibility_trusted=False,
                input_monitoring_allowed=False,
                can_post_keyboard_events=False,
                notes=(self._missing_dependency_note(),),
            )

        accessibility_trusted = self._check_accessibility_trust()
        input_monitoring_allowed = self._check_input_monitoring()
        can_post_keyboard_events = self._check_keyboard_posting()

        notes: list[str] = []
        if not accessibility_trusted:
            notes.append(
                "Accessibility permission is required for the global event tap and event injection."
            )
        if not input_monitoring_allowed:
            notes.append(
                "Input Monitoring permission is required to observe key events globally."
            )
        if not can_post_keyboard_events:
            notes.append(
                "Keyboard event posting is not currently available on this system."
            )

        return PermissionReport(
            accessibility_trusted=accessibility_trusted,
            input_monitoring_allowed=input_monitoring_allowed,
            can_post_keyboard_events=can_post_keyboard_events,
            notes=tuple(notes),
        )

    def request_permissions(self) -> PermissionReport:
        self._ensure_available()
        self._request_accessibility_permission()
        request_listen = getattr(Quartz, "CGRequestListenEventAccess", None)
        request_post = getattr(Quartz, "CGRequestPostEventAccess", None)

        try:
            if callable(request_listen):
                request_listen()
        except Exception:
            pass

        try:
            if callable(request_post):
                request_post()
        except Exception:
            pass

        return self.check_permissions()

    # ------------------------------------------------------------------
    # Compatibility helpers
    # ------------------------------------------------------------------
    def is_target_frontmost(self) -> bool:
        """Return whether the configured target application is frontmost."""

        return self.is_frontmost_bundle(self.target_bundle_id)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------
    def _ensure_available(self) -> None:
        if PYOBJC_AVAILABLE:
            return
        raise RuntimeError(
            "PyObjC/Quartz is not available. Install the macOS dependencies to use "
            f"the platform adapter: {self._missing_dependency_note()}"
        ) from PYOBJC_IMPORT_ERROR

    def _missing_dependency_note(self) -> str:
        return (
            "missing PyObjC bindings for AppKit/Foundation/Quartz"
            if PYOBJC_IMPORT_ERROR is None
            else f"import error: {PYOBJC_IMPORT_ERROR}"
        )

    def _validate_permissions_for_hook(self) -> None:
        report = self.check_permissions()
        if report.ready:
            return
        missing = ", ".join(report.missing_permissions()) or "unknown permissions"
        notes = " ".join(report.notes)
        raise PlatformError(
            "macOS key hook cannot start until the required permissions are granted: "
            f"{missing}. {notes}".strip()
        )

    def _run_hook_loop(self) -> None:
        try:
            tap = self._create_event_tap()
            if tap is None:
                raise PlatformError(
                    "Unable to create the Quartz event tap. Accessibility permission "
                    "is likely missing."
                )

            source = Quartz.CFMachPortCreateRunLoopSource(None, tap, 0)
            run_loop = Quartz.CFRunLoopGetCurrent()

            with self._lock:
                self._tap = tap
                self._run_loop = run_loop
                self._run_loop_source = source

            Quartz.CFRunLoopAddSource(run_loop, source, Quartz.kCFRunLoopCommonModes)
            Quartz.CGEventTapEnable(tap, True)
            self._hook_ready.set()
            Quartz.CFRunLoopRun()
        except Exception as exc:
            self._hook_error = exc
            self._hook_ready.set()
        finally:
            try:
                if self._tap is not None:
                    Quartz.CGEventTapEnable(self._tap, False)
            except Exception:
                pass

            try:
                if self._run_loop is not None and self._run_loop_source is not None:
                    Quartz.CFRunLoopRemoveSource(
                        self._run_loop, self._run_loop_source, Quartz.kCFRunLoopCommonModes
                    )
            except Exception:
                pass

    def _create_event_tap(self):
        event_mask = Quartz.CGEventMaskBit(Quartz.kCGEventKeyDown)

        def callback(proxy, event_type, event, refcon):  # noqa: ANN001, ANN201
            disabled_by_timeout = getattr(Quartz, "kCGEventTapDisabledByTimeout", None)
            disabled_by_user_input = getattr(Quartz, "kCGEventTapDisabledByUserInput", None)

            if event_type in {disabled_by_timeout, disabled_by_user_input}:
                if self._tap is not None:
                    Quartz.CGEventTapEnable(self._tap, True)
                return event

            if event_type != Quartz.kCGEventKeyDown:
                return event

            try:
                keycode = int(
                    Quartz.CGEventGetIntegerValueField(
                        event, Quartz.kCGKeyboardEventKeycode
                    )
                )
                key_name = self._key_name_for_keycode(keycode)
                if key_name is None:
                    return event

                is_repeat = self._is_repeat_event(event)
                key_event = KeyEvent(
                    key=key_name,
                    keycode=keycode,
                    is_repeat=is_repeat,
                )

                handler = self._handler
                if handler is None:
                    return None

                consume = bool(handler(key_event))
                return None if consume else event
            except Exception as exc:
                self._hook_error = exc
                return event

        tap = Quartz.CGEventTapCreate(
            Quartz.kCGSessionEventTap,
            Quartz.kCGHeadInsertEventTap,
            Quartz.kCGEventTapOptionDefault,
            event_mask,
            callback,
            None,
        )
        return tap

    def _key_name_for_keycode(self, keycode: int) -> str | None:
        if keycode == _SPACE_KEYCODE:
            return "space"
        if keycode in {_RETURN_KEYCODE, _KEYPAD_RETURN_KEYCODE}:
            return "return"
        if keycode == _DELETE_KEYCODE:
            return "delete"
        return None

    def _is_repeat_event(self, event) -> bool:  # noqa: ANN001
        repeat_field = getattr(Quartz, "kCGKeyboardEventAutorepeat", None)
        if repeat_field is None:
            return False
        try:
            return bool(Quartz.CGEventGetIntegerValueField(event, repeat_field))
        except Exception:
            return False

    def _post_unicode_character(self, char: str) -> None:
        event = Quartz.CGEventCreateKeyboardEvent(None, 0, True)
        if hasattr(Quartz, "CGEventKeyboardSetUnicodeString"):
            Quartz.CGEventKeyboardSetUnicodeString(event, 1, char)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

        key_up = Quartz.CGEventCreateKeyboardEvent(None, 0, False)
        if hasattr(Quartz, "CGEventKeyboardSetUnicodeString"):
            Quartz.CGEventKeyboardSetUnicodeString(key_up, 1, char)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, key_up)

    def _post_keycode(self, keycode: int) -> None:
        for is_key_down in (True, False):
            event = Quartz.CGEventCreateKeyboardEvent(None, keycode, is_key_down)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

    def _check_input_monitoring(self) -> bool:
        preflight = getattr(Quartz, "CGPreflightListenEventAccess", None)
        if preflight is None:
            return True
        try:
            return bool(preflight())
        except Exception:
            return False

    def _check_keyboard_posting(self) -> bool:
        preflight = getattr(Quartz, "CGPreflightPostEventAccess", None)
        if preflight is None:
            return True
        try:
            return bool(preflight())
        except Exception:
            return False

    def _check_accessibility_trust(self) -> bool:
        try:
            application_services = ctypes.CDLL(_APPLICATION_SERVICES_PATH)
            function = application_services.AXIsProcessTrusted
            function.restype = ctypes.c_bool
            return bool(function())
        except Exception:
            return False

    def _request_accessibility_permission(self) -> None:
        if not PYOBJC_AVAILABLE:
            return
        try:
            application_services = ctypes.CDLL(_APPLICATION_SERVICES_PATH)
            function = application_services.AXIsProcessTrustedWithOptions
            function.argtypes = [ctypes.c_void_p]
            function.restype = ctypes.c_bool

            options = Foundation.NSDictionary.dictionaryWithObject_forKey_(
                Foundation.NSNumber.numberWithBool_(True),
                "AXTrustedCheckOptionPrompt",
            )
            function(ctypes.c_void_p(objc.pyobjc_id(options)))
        except Exception:
            pass


# Backwards compatible aliases.
MacOSPlatform = MacOSPlatformAdapter
