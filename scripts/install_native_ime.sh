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

if [[ -e "${DESTINATION_PATH}" ]]; then
  rm -rf "${DESTINATION_PATH}"
fi

ditto "${APP_PATH}" "${DESTINATION_PATH}"
codesign --verify --deep --strict "${DESTINATION_PATH}"

echo "Installed to: ${DESTINATION_PATH}"
echo "Next steps:"
echo "1. Open the installed app once and choose a txt source."
echo "2. Add or re-enable '摸鱼助手输入法' in System Settings -> Keyboard -> Input Sources."
echo "3. Switch to the input method, set Armed, then test in Word or WPS Writer."

if [[ "${LAUNCH_AFTER_INSTALL}" -eq 1 ]]; then
  open "${DESTINATION_PATH}"
fi
