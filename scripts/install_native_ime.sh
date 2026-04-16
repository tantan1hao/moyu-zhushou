#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT}/MoyuAssistant.xcodeproj"
SPEC_PATH="${ROOT}/project.yml"

CONFIGURATION="Release"
DERIVED_DATA_PATH="${ROOT}/DerivedData"
INSTALL_DIR="${HOME}/Library/Input Methods"
LAUNCH_AFTER_INSTALL=0
REGENERATE_PROJECT=1
SKIP_BUILD=0
SIGNING_MODE="adhoc"
DEVELOPMENT_TEAM_ID="${DEVELOPMENT_TEAM_ID:-}"

bundle_identifier_for_app() {
  local app_path="$1"
  local plist_path="${app_path}/Contents/Info.plist"

  if [[ -f "${plist_path}" ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${plist_path}" 2>/dev/null || true
  fi
}

clean_install_artifacts() {
  rm -rf \
    "${DESTINATION_PATH}" \
    "${INSTALL_DIR}/MoyuAssistant.app.dSYM" \
    "${INSTALL_DIR}/MoyuAssistant.swiftmodule" \
    "${INSTALL_DIR}/MoyuInputMethodExtension.appex" \
    "${INSTALL_DIR}/MoyuInputMethodExtension.appex.dSYM" \
    "${INSTALL_DIR}/MoyuInputMethodExtension.swiftmodule" \
    "${INSTALL_DIR}/NovelIMECore.framework" \
    "${INSTALL_DIR}/NovelIMECore.framework.dSYM" \
    "${INSTALL_DIR}/NovelIMECore.swiftmodule" \
    "${INSTALL_DIR}/libNovelIMECore.a" \
    "${INSTALL_DIR}/include"
}

register_input_source() {
  local bundle_path="$1"
  local bundle_id=""
  local input_mode_id=""
  local temp_dir helper_source helper_binary
  local helper_status=0

  bundle_id="$(bundle_identifier_for_app "${bundle_path}")"
  input_mode_id="$(/usr/libexec/PlistBuddy -c 'Print :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0' "${bundle_path}/Contents/Info.plist" 2>/dev/null || true)"

  temp_dir="$(mktemp -d)"
  helper_source="${temp_dir}/register_input_source.m"
  helper_binary="${temp_dir}/register_input_source"

  cat > "${helper_source}" <<'EOF'
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

static NSString *StringForProperty(TISInputSourceRef source, CFStringRef key) {
    CFTypeRef value = TISGetInputSourceProperty(source, key);
    return value ? [(__bridge id)value description] : @"";
}

static void EnsureEnabledInputSourceEntries(NSString *bundleID, NSString *inputModeID) {
    if (bundleID.length == 0) {
        return;
    }

    NSString *domain = @"com.apple.HIToolbox";
    NSArray *existing = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)@"AppleEnabledInputSources",
                                                                    (__bridge CFStringRef)domain));
    NSMutableArray *mutableEntries = existing ? [existing mutableCopy] : [NSMutableArray array];

    NSDictionary *keyboardMethodEntry = @{
        @"Bundle ID": bundleID,
        @"InputSourceKind": @"Keyboard Input Method",
    };

    NSDictionary *keyboardMethodWithSourceIDEntry = @{
        @"Bundle ID": bundleID,
        @"Input Source ID": bundleID,
        @"InputSourceKind": @"Keyboard Input Method",
    };

    if (![mutableEntries containsObject:keyboardMethodEntry]) {
        [mutableEntries addObject:keyboardMethodEntry];
    }
    if (![mutableEntries containsObject:keyboardMethodWithSourceIDEntry]) {
        [mutableEntries addObject:keyboardMethodWithSourceIDEntry];
    }

    if (inputModeID.length > 0) {
        NSDictionary *inputModeEntry = @{
            @"Bundle ID": bundleID,
            @"Input Mode": inputModeID,
            @"InputSourceKind": @"Input Mode",
        };
        if (![mutableEntries containsObject:inputModeEntry]) {
            [mutableEntries addObject:inputModeEntry];
        }
    }

    CFPreferencesSetAppValue((__bridge CFStringRef)@"AppleEnabledInputSources",
                             (__bridge CFPropertyListRef)mutableEntries,
                             (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}

static void EnsureSelectedInputSourceEntry(NSString *bundleID, NSString *inputModeID) {
    if (bundleID.length == 0 || inputModeID.length == 0) {
        return;
    }

    NSString *domain = @"com.apple.HIToolbox";
    NSArray *selectedEntries = @[
        @{
            @"Bundle ID": bundleID,
            @"Input Mode": inputModeID,
            @"InputSourceKind": @"Input Mode",
        }
    ];

    CFPreferencesSetAppValue((__bridge CFStringRef)@"AppleSelectedInputSources",
                             (__bridge CFPropertyListRef)selectedEntries,
                             (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *bundlePath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        NSString *bundleID = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"";
        NSString *inputModeID = argc > 3 ? [NSString stringWithUTF8String:argv[3]] : @"";

        if (bundlePath.length == 0) {
            fprintf(stderr, "register_input_source: missing bundle path\n");
            return 2;
        }

        NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];
        OSStatus registerStatus = TISRegisterInputSource((__bridge CFURLRef)bundleURL);
        printf("TISRegisterInputSource(%s) = %d\n", bundlePath.UTF8String, (int)registerStatus);

        if (bundleID.length == 0) {
            return registerStatus == noErr ? 0 : (int)registerStatus;
        }

        NSDictionary *filter = @{ (__bridge NSString *)kTISPropertyBundleID: bundleID };
        NSArray *sources = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true));
        if (sources.count == 0) {
            printf("No TIS sources found for bundle id %s after registration\n", bundleID.UTF8String);
            return registerStatus == noErr ? 3 : (int)registerStatus;
        }

        for (id sourceObject in sources) {
            TISInputSourceRef source = (__bridge TISInputSourceRef)sourceObject;
            NSString *inputSourceID = StringForProperty(source, kTISPropertyInputSourceID);
            CFBooleanRef enableCapableValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnableCapable);
            Boolean enableCapable = enableCapableValue ? CFBooleanGetValue(enableCapableValue) : false;
            printf("Registered input source: %s (enableCapable=%d)\n", inputSourceID.UTF8String, (int)enableCapable);
            if (enableCapable) {
                OSStatus enableStatus = TISEnableInputSource(source);
                printf("TISEnableInputSource(%s) = %d\n", inputSourceID.UTF8String, (int)enableStatus);
            }
        }

        EnsureEnabledInputSourceEntries(bundleID, inputModeID);
        EnsureSelectedInputSourceEntry(bundleID, inputModeID);

        return registerStatus == noErr ? 0 : (int)registerStatus;
    }
}
EOF

  if command -v clang >/dev/null 2>&1 && \
    clang -fobjc-arc -framework Foundation -framework Carbon "${helper_source}" -o "${helper_binary}"; then
    "${helper_binary}" "${bundle_path}" "${bundle_id}" "${input_mode_id}" 2>/dev/null || helper_status=$?
  else
    echo "Warning: failed to compile TIS registration helper; skipping explicit input-source registration." >&2
  fi

  rm -rf "${temp_dir}"
  return "${helper_status}"
}

verify_input_source_registration() {
  local bundle_id="$1"
  local temp_dir helper_source helper_binary
  local helper_status=1
  local attempt_output=""

  if [[ -z "${bundle_id}" ]]; then
    return 1
  fi

  temp_dir="$(mktemp -d)"
  helper_source="${temp_dir}/check_input_source_visibility.m"
  helper_binary="${temp_dir}/check_input_source_visibility"

  cat > "${helper_source}" <<'EOF'
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

static NSString *StringForProperty(TISInputSourceRef source, CFStringRef key) {
    CFTypeRef value = TISGetInputSourceProperty(source, key);
    return value ? [(__bridge id)value description] : @"";
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *bundleID = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        if (bundleID.length == 0) {
            fprintf(stderr, "check_input_source_visibility: missing bundle id\n");
            return 2;
        }

        NSArray *sources = CFBridgingRelease(TISCreateInputSourceList(NULL, true));
        NSInteger matches = 0;
        for (id sourceObject in sources) {
            TISInputSourceRef source = (__bridge TISInputSourceRef)sourceObject;
            NSString *inputSourceID = StringForProperty(source, kTISPropertyInputSourceID);
            NSString *sourceBundleID = StringForProperty(source, kTISPropertyBundleID);
            if ([inputSourceID isEqualToString:bundleID] || [sourceBundleID isEqualToString:bundleID]) {
                matches += 1;
            }
        }

        printf("TIS visible matches for %s: %ld\n", bundleID.UTF8String, (long)matches);
        return matches > 0 ? 0 : 1;
    }
}
EOF

  if command -v clang >/dev/null 2>&1 && \
    clang -fobjc-arc -framework Foundation -framework Carbon "${helper_source}" -o "${helper_binary}"; then
    for attempt in $(seq 1 10); do
      if attempt_output="$("${helper_binary}" "${bundle_id}" 2>/dev/null)"; then
        echo "${attempt_output}"
        helper_status=0
        break
      fi

      if [[ "${attempt}" -lt 10 ]]; then
        sleep 1
      fi
    done
  else
    echo "Warning: failed to compile TIS visibility helper; skipping post-install verification." >&2
    helper_status=0
  fi

  if [[ "${helper_status}" -ne 0 ]]; then
    echo "${attempt_output}" >&2
    echo "Warning: input source is still not visible in TIS after waiting." >&2
  fi

  rm -rf "${temp_dir}"
  return "${helper_status}"
}

usage() {
  cat <<'EOF'
Usage: scripts/install_native_ime.sh [options]

Builds the native macOS input method host app, then installs it into the
selected Input Methods folder.

Options:
  --configuration <name>   Build configuration. Default: Release
  --derived-data-path <p>  DerivedData output path. Default: ./DerivedData
  --install-dir <path>     Install destination directory. Default:
                           ~/Library/Input Methods
  --launch                 Open the installed app after copy
  --no-launch              Do not open the installed app after copy. Default behavior.
  --team <id>              Use Apple automatic signing with this Team ID.
                           You can also set DEVELOPMENT_TEAM_ID.
  --automatic-signing      Use Apple automatic signing without overriding Team.
  --ad-hoc-signing         Use local ad-hoc signing. Default unless a Team ID is set.
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
    --no-launch)
      LAUNCH_AFTER_INSTALL=0
      shift
      ;;
    --team)
      [[ $# -ge 2 ]] || { echo "Missing value for --team" >&2; exit 1; }
      DEVELOPMENT_TEAM_ID="$2"
      SIGNING_MODE="automatic"
      shift 2
      ;;
    --automatic-signing)
      SIGNING_MODE="automatic"
      shift
      ;;
    --ad-hoc-signing)
      SIGNING_MODE="adhoc"
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
BUILT_IN_PLACE=0

if [[ -n "${DEVELOPMENT_TEAM_ID}" ]]; then
  SIGNING_MODE="automatic"
fi

mkdir -p "${INSTALL_DIR}"

if pgrep -f "${DESTINATION_PATH}/Contents/MacOS/MoyuAssistant" >/dev/null 2>&1; then
  pkill -f "${DESTINATION_PATH}/Contents/MacOS/MoyuAssistant"
  sleep 1
fi

if [[ "${SIGNING_MODE}" == "automatic" ]]; then
  clean_install_artifacts
fi

if [[ "${REGENERATE_PROJECT}" -eq 1 ]]; then
  command -v xcodegen >/dev/null 2>&1 || {
    echo "xcodegen is required unless --skip-xcodegen is used." >&2
    exit 1
  }

  xcodegen generate --spec "${SPEC_PATH}" --project "${ROOT}"
fi

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  build_args=(
    build
    -project "${PROJECT_PATH}"
    -scheme MoyuAssistant
    -configuration "${CONFIGURATION}"
    -destination 'platform=macOS'
    -derivedDataPath "${DERIVED_DATA_PATH}"
  )

  if [[ "${SIGNING_MODE}" == "automatic" ]]; then
    BUILT_IN_PLACE=1
    APP_PATH="${INSTALL_DIR}/MoyuAssistant.app"
    build_args+=(
      -allowProvisioningUpdates
      "CONFIGURATION_BUILD_DIR=${INSTALL_DIR}"
      CODE_SIGN_STYLE=Automatic
      CODE_SIGN_IDENTITY="Apple Development"
    )
    if [[ -n "${DEVELOPMENT_TEAM_ID}" ]]; then
      build_args+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM_ID}")
    fi
  else
    build_args+=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY=-
      DEVELOPMENT_TEAM=
    )
  fi

  xcodebuild "${build_args[@]}"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Built app not found at: ${APP_PATH}" >&2
  exit 1
fi

if [[ "${BUILT_IN_PLACE}" -eq 1 ]]; then
  rm -rf \
    "${INSTALL_DIR}/MoyuAssistant.app.dSYM" \
    "${INSTALL_DIR}/MoyuAssistant.swiftmodule" \
    "${INSTALL_DIR}/MoyuInputMethodExtension.appex" \
    "${INSTALL_DIR}/MoyuInputMethodExtension.appex.dSYM" \
    "${INSTALL_DIR}/MoyuInputMethodExtension.swiftmodule" \
    "${INSTALL_DIR}/NovelIMECore.framework" \
    "${INSTALL_DIR}/NovelIMECore.framework.dSYM" \
    "${INSTALL_DIR}/NovelIMECore.swiftmodule" \
    "${INSTALL_DIR}/libNovelIMECore.a" \
    "${INSTALL_DIR}/include"
fi

if [[ "${BUILT_IN_PLACE}" -eq 0 && -e "${DESTINATION_PATH}" ]]; then
  clean_install_artifacts
fi

if [[ "${BUILT_IN_PLACE}" -eq 0 ]]; then
  ditto "${APP_PATH}" "${DESTINATION_PATH}"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "${APP_PATH}" >/dev/null 2>&1 || true
fi

bundle_id="$(bundle_identifier_for_app "${DESTINATION_PATH}")"
codesign --verify --deep --strict "${DESTINATION_PATH}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R -trusted "${DESTINATION_PATH}"
register_input_source "${DESTINATION_PATH}"
sleep 2
register_input_source "${DESTINATION_PATH}" || true

if [[ -n "${bundle_id}" ]] && ! verify_input_source_registration "${bundle_id}"; then
  echo "Retrying TIS registration once..." >&2
  register_input_source "${DESTINATION_PATH}" || true
  verify_input_source_registration "${bundle_id}" || true
fi

echo "Installed to: ${DESTINATION_PATH}"
echo "Signing mode: ${SIGNING_MODE}"
echo "Next steps:"
echo "1. This developer install path is only for local debugging."
echo "2. For first-time daily use, prefer the system pkg: /Users/mac/word/scripts/build_input_method_pkg.sh"
echo "3. In System Settings -> Keyboard -> Input Sources, add or re-enable '摸鱼助手输入法'."
echo "4. If it still does not appear, fully quit and reopen System Settings once before checking again."
echo "5. After the input method is visible, open the installed app manually to choose a txt source."
echo "6. Click '开启 Armed', switch to the input method, then test in Word or WPS Writer."

if [[ "${LAUNCH_AFTER_INSTALL}" -eq 1 ]]; then
  open "${DESTINATION_PATH}" --args --show-settings
fi
