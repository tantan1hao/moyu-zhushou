#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT}/MoyuAssistant.xcodeproj"
SPEC_PATH="${ROOT}/project.yml"
CONFIGURATION="Release"
DIST_DIR="${ROOT}/dist"
OUTPUT_PKG="${DIST_DIR}/MoyuAssistant.pkg"
COMPONENT_PKG_IDENTIFIER="com.tantan1hao.inputmethod.moyuassistant.component"
PRODUCT_PKG_IDENTIFIER="com.tantan1hao.inputmethod.moyuassistant.pkg"
USER_LOCAL_APP="${HOME}/Library/Input Methods/MoyuAssistant.app"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/moyu_pkg_build.XXXXXX")"
DERIVED_DATA_PATH="${build_root}/DerivedData"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/MoyuAssistant.app"
COMPONENT_PKG="${build_root}/MoyuAssistant.component.pkg"
COMPONENT_PKG_DIR="${build_root}/packages"
SCRIPTS_DIR="${ROOT}/package/scripts"
DIST_XML="${build_root}/Distribution.xml"

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required." >&2
  exit 1
}

command -v pkgbuild >/dev/null 2>&1 || {
  echo "pkgbuild is required." >&2
  exit 1
}

command -v productbuild >/dev/null 2>&1 || {
  echo "productbuild is required." >&2
  exit 1
}

find_signing_identity() {
  security find-identity -p codesigning -v 2>/dev/null \
    | awk '/Apple Development:/ { print $2; exit }'
}

echo "Generating Xcode project..."
xcodegen generate --spec "${SPEC_PATH}" --project "${ROOT}"

echo "Building release app..."
xcodebuild build \
  -project "${PROJECT_PATH}" \
  -scheme MoyuAssistant \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Built app not found at: ${APP_PATH}" >&2
  exit 1
fi

signing_identity="$(find_signing_identity || true)"
if [[ -n "${signing_identity}" ]]; then
  echo "Re-signing app with Apple Development identity ${signing_identity}..."
  entitlements_path="${build_root}/MoyuAssistant.entitlements"
  codesign -d --entitlements :- "${APP_PATH}" > "${entitlements_path}" 2>/dev/null || true
  if [[ -s "${entitlements_path}" ]]; then
    codesign --force --sign "${signing_identity}" --timestamp=none --entitlements "${entitlements_path}" "${APP_PATH}"
  else
    codesign --force --sign "${signing_identity}" --timestamp=none "${APP_PATH}"
  fi
else
  echo "No Apple Development identity found, keeping ad-hoc signature."
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/moyu_pkg_root.XXXXXX")"
trap 'rm -rf "${tmp_root}" "${build_root}"' EXIT
mkdir -p "${tmp_root}"
ditto "${APP_PATH}" "${tmp_root}/MoyuAssistant.app"

component_plist="${build_root}/components.plist"
pkgbuild --analyze --root "${tmp_root}" "${component_plist}" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "${component_plist}"

mkdir -p "${DIST_DIR}"
rm -f "${OUTPUT_PKG}"
/bin/chmod +x "${SCRIPTS_DIR}/preinstall" "${SCRIPTS_DIR}/postinstall"

if [[ -d "${USER_LOCAL_APP}" ]]; then
  echo "Warning: user-local install exists at ${USER_LOCAL_APP}."
  echo "Remove or rename it before installing the pkg, otherwise macOS Installer may relocate the system install back into ~/Library/Input Methods."
fi

mkdir -p "${COMPONENT_PKG_DIR}"

echo "Building component package..."
pkgbuild \
  --root "${tmp_root}" \
  --scripts "${SCRIPTS_DIR}" \
  --component-plist "${component_plist}" \
  --identifier "${COMPONENT_PKG_IDENTIFIER}" \
  --version "1.0" \
  --install-location "/Library/Input Methods" \
  "${COMPONENT_PKG}"

productbuild --synthesize --package "${COMPONENT_PKG}" "${DIST_XML}"

python3 - <<PY
from pathlib import Path
import xml.etree.ElementTree as ET

path = Path("${DIST_XML}")
tree = ET.parse(path)
root = tree.getroot()

title = root.find("title")
if title is None:
    title = ET.SubElement(root, "title")
title.text = "摸鱼助手输入法"

options = root.find("options")
if options is None:
    options = ET.SubElement(root, "options")
options.set("customize", "never")
options.set("require-scripts", "false")
options.set("hostArchitectures", "arm64,x86_64")
options.set("postinstall-action", "logout")

domains = root.find("domains")
if domains is None:
    domains = ET.SubElement(root, "domains")
domains.set("enable_anywhere", "false")
domains.set("enable_currentUserHome", "false")
domains.set("enable_localSystem", "true")

ET.indent(tree, space="    ")
tree.write(path, encoding="utf-8", xml_declaration=True)
PY

echo "Building product package..."
productbuild \
  --distribution "${DIST_XML}" \
  --package-path "${build_root}" \
  --identifier "${PRODUCT_PKG_IDENTIFIER}" \
  "${OUTPUT_PKG}"

echo "Package ready: ${OUTPUT_PKG}"
echo "Recommended next steps:"
echo "1. Remove any existing ~/Library/Input Methods/MoyuAssistant.app first."
echo "2. Double-click the pkg and install it to /Library/Input Methods."
echo "3. The installer will register and enable the input source, then ask for logout."
echo "4. Log out and log back in once."
echo "5. Open System Settings -> Keyboard -> Input Sources and look for '摸鱼助手' / 'Moyu Assistant'."
