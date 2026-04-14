"""Platform adapters exposed by novel_ime."""

from __future__ import annotations

import sys

from .base import (
    BasePlatform,
    KeyEvent,
    PermissionReport,
    PlatformAdapter,
    PlatformError,
    first_present,
    normalize_bundle_id,
)
from .macos import DEFAULT_TARGET_BUNDLE_ID, MacOSPlatform, MacOSPlatformAdapter

__all__ = [
    "DEFAULT_TARGET_BUNDLE_ID",
    "BasePlatform",
    "KeyEvent",
    "MacOSPlatform",
    "MacOSPlatformAdapter",
    "PermissionReport",
    "PlatformAdapter",
    "PlatformError",
    "create_platform_adapter",
    "first_present",
    "normalize_bundle_id",
]


def create_platform_adapter(
    target_bundle_id: str = DEFAULT_TARGET_BUNDLE_ID,
) -> PlatformAdapter:
    """Create the default adapter for the current interpreter/platform."""

    if sys.platform == "darwin":
        return MacOSPlatformAdapter(target_bundle_id=target_bundle_id)
    raise PlatformError(
        "No platform adapter is available for this operating system. "
        "The current implementation only provides a macOS backend."
    )
