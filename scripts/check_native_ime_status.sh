#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Library/Input Methods/MoyuAssistant.app"
APP_BINARY="${APP_PATH}/Contents/MacOS/MoyuAssistant"

if [[ ! -x "${APP_BINARY}" ]]; then
  echo "Installed app binary not found: ${APP_BINARY}" >&2
  exit 1
fi

echo "AppleSelectedInputSources:"
defaults read com.apple.HIToolbox AppleSelectedInputSources || true
echo
echo "Current selected input source:"
"${APP_BINARY}" --print-current-input-source || true
echo
echo "Selection verification:"
if "${APP_BINARY}" --verify-input-source; then
  echo "verified=true"
else
  echo "verified=false"
  exit 1
fi
