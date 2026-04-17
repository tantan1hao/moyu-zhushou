#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT}/MoyuAssistant.xcodeproj"
SPEC_PATH="${ROOT}/project.yml"

CONFIGURATION="Debug"
DERIVED_DATA_PATH="${ROOT}/DerivedData"
INSTALL_DIR="${HOME}/Library/Input Methods"
LAUNCH_AFTER_INSTALL=0
REGENERATE_PROJECT=1
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/install_native_ime.sh [options]

Builds the native macOS input method host app, then installs it into the
selected Input Methods folder.

Options:
  --configuration <name>   Build configuration. Default: Debug
  --derived-data-path <p>  DerivedData output path. Default: ./DerivedData
  --install-dir <path>     Install destination directory. Default:
                           ~/Library/Input Methods
  --launch                 Open the installed app after copy
  --skip-xcodegen          Reuse the existing .xcodeproj without regenerating
  --skip-build             Reuse the existing built app without rebuilding
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { echo "Missing value for --configuration" >&2; exit 1; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --derived-data-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --derived-data-path" >&2; exit 1; }
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for --install-dir" >&2; exit 1; }
      INSTALL_DIR="$2"
      shift 2
      ;;
    --launch)
      LAUNCH_AFTER_INSTALL=1
      shift
      ;;
    --skip-xcodegen)
      REGENERATE_PROJECT=0
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/MoyuAssistant.app"
DESTINATION_PATH="${INSTALL_DIR}/MoyuAssistant.app"
APP_BINARY="${DESTINATION_PATH}/Contents/MacOS/MoyuAssistant"
INPUT_MODE_ID="com.tantan1hao.moyuassistant.mode.default"
SOURCE_HOST_INFO_PLIST="${ROOT}/NativeIME/HostApp/Info.plist"

inject_input_method_plist_keys() {
  python3 - "${SOURCE_HOST_INFO_PLIST}" "${DESTINATION_PATH}/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
dest_path = Path(sys.argv[2])

with source_path.open("rb") as fh:
    source = plistlib.load(fh)
with dest_path.open("rb") as fh:
    dest = plistlib.load(fh)

keys = [
    "ComponentInputModeDict",
    "InputMethodConnectionName",
    "InputMethodServerControllerClass",
    "LSUIElement",
    "TISInputSourceID",
    "TISIntendedLanguage",
    "tsInputMethodCharacterRepertoireKey",
]

for key in keys:
    if key in source:
        dest[key] = source[key]

with dest_path.open("wb") as fh:
    plistlib.dump(dest, fh)
PY
}

run_app_command() {
  "${APP_BINARY}" "$@"
}

verify_selection() {
  run_app_command --verify-input-source
}

if [[ "${REGENERATE_PROJECT}" -eq 1 ]]; then
  command -v xcodegen >/dev/null 2>&1 || {
    echo "xcodegen is required unless --skip-xcodegen is used." >&2
    exit 1
  }

  xcodegen generate --spec "${SPEC_PATH}" --project "${ROOT}"
fi

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  xcodebuild build \
    -project "${PROJECT_PATH}" \
    -scheme MoyuAssistant \
    -configuration "${CONFIGURATION}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM=
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Built app not found at: ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"

pkill -f MoyuAssistant || true
rm -rf "${HOME}/Library/Input Methods/MoyuAssistant.app"
rm -rf "${DESTINATION_PATH}"

ditto "${APP_PATH}" "${DESTINATION_PATH}"
inject_input_method_plist_keys
codesign --force --deep --sign - "${DESTINATION_PATH}"
codesign --verify --deep --strict "${DESTINATION_PATH}"

run_app_command --register-input-source
run_app_command --enable-input-source

selection_verified=0
for attempt in 1 2 3 4 5; do
  run_app_command --select-input-source || true
  sleep 1
  if verify_selection; then
    selection_verified=1
    break
  fi
done

echo "AppleSelectedInputSources:"
defaults read com.apple.HIToolbox AppleSelectedInputSources || true
echo
echo "Current selected input source:"
run_app_command --print-current-input-source || true
echo

if [[ "${selection_verified}" -ne 1 ]]; then
  echo "Failed to verify that ${INPUT_MODE_ID} is the selected input source." >&2
  exit 1
fi

echo "Installed to: ${DESTINATION_PATH}"
echo "Next steps:"
echo "1. Open the installed app once and choose a txt source."
echo "2. Keep '摸鱼助手输入法' selected and turn Armed on."
echo "3. Smoke test in TextEdit first, then Microsoft Word, then WPS Writer."

if [[ "${LAUNCH_AFTER_INSTALL}" -eq 1 ]]; then
  open "${DESTINATION_PATH}"
fi
