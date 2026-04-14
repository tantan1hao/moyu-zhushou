"""Platform abstraction for the word novel proxy."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Callable, Iterable


@dataclass(frozen=True, slots=True)
class KeyEvent:
    """Normalized key event exposed to the platform-agnostic core."""

    key: str
    keycode: int | None = None
    is_repeat: bool = False
    modifiers: frozenset[str] = field(default_factory=frozenset)

    def is_interceptable(self) -> bool:
        return self.key in {"space", "return", "delete"}


@dataclass(frozen=True, slots=True)
class PermissionReport:
    """Permission state needed by the macOS adapter."""

    accessibility_trusted: bool
    input_monitoring_allowed: bool
    can_post_keyboard_events: bool = True
    notes: tuple[str, ...] = ()

    @property
    def ready(self) -> bool:
        return (
            self.accessibility_trusted
            and self.input_monitoring_allowed
            and self.can_post_keyboard_events
        )

    def missing_permissions(self) -> tuple[str, ...]:
        missing: list[str] = []
        if not self.accessibility_trusted:
            missing.append("Accessibility")
        if not self.input_monitoring_allowed:
            missing.append("Input Monitoring")
        if not self.can_post_keyboard_events:
            missing.append("Keyboard Event Posting")
        return tuple(missing)


class PlatformError(RuntimeError):
    """Raised when a platform adapter cannot satisfy the requested operation."""


class PlatformAdapter(ABC):
    """Platform-independent interface used by the application core.

    The hook callback returns ``True`` to consume the original event and
    ``False``/``None`` to let it through.
    """

    @abstractmethod
    def start_hook(
        self, handler: Callable[[KeyEvent], bool | None] | None = None
    ) -> None:
        """Start the global key hook."""

    @abstractmethod
    def stop_hook(self) -> None:
        """Stop the global key hook and release native resources."""

    @abstractmethod
    def get_frontmost_app(self) -> str | None:
        """Return the bundle id of the frontmost application, if available."""

    @abstractmethod
    def inject_text(self, text: str) -> None:
        """Inject text into the active application."""

    @abstractmethod
    def inject_backspace(self, count: int = 1) -> None:
        """Inject one or more backspace presses."""

    @abstractmethod
    def check_permissions(self) -> PermissionReport:
        """Return the current platform permission state."""

    def request_permissions(self) -> PermissionReport:
        """Request or prompt for the required permissions when supported."""

        return self.check_permissions()

    def is_frontmost_bundle(self, bundle_id: str) -> bool:
        """Return whether the given bundle id is currently frontmost."""

        current = self.get_frontmost_app()
        return current == bundle_id

    # Compatibility aliases for older camelCase callers.
    def startHook(
        self, handler: Callable[[KeyEvent], bool | None] | None = None
    ) -> None:  # noqa: N802
        self.start_hook(handler)

    def stopHook(self) -> None:  # noqa: N802
        self.stop_hook()

    def getFrontmostApp(self) -> str | None:  # noqa: N802
        return self.get_frontmost_app()

    def injectText(self, text: str) -> None:  # noqa: N802
        self.inject_text(text)

    def injectBackspace(self, count: int = 1) -> None:  # noqa: N802
        self.inject_backspace(count)

    def checkPermissions(self) -> PermissionReport:  # noqa: N802
        return self.check_permissions()

    def requestPermissions(self) -> PermissionReport:  # noqa: N802
        return self.request_permissions()


BasePlatform = PlatformAdapter


def normalize_bundle_id(bundle_id: str | None) -> str | None:
    """Normalize a bundle id before comparing it against the target app."""

    if bundle_id is None:
        return None
    candidate = bundle_id.strip()
    return candidate or None


def first_present(values: Iterable[str | None]) -> str | None:
    """Return the first non-empty string from a sequence."""

    for value in values:
        normalized = normalize_bundle_id(value)
        if normalized is not None:
            return normalized
    return None
