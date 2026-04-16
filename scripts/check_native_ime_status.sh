#!/usr/bin/env bash
set -euo pipefail

SYSTEM_APP="/Library/Input Methods/MoyuAssistant.app"
USER_APP="${HOME}/Library/Input Methods/MoyuAssistant.app"
BUNDLE_ID="com.tantan1hao.inputmethod.moyuassistant"
INPUT_MODE_ID="com.tantan1hao.inputmethod.moyuassistant.default"

print_presence() {
  local label="$1"
  local path="$2"
  if [[ -d "${path}" ]]; then
    printf "%-18s %s\n" "${label}:" "${path}"
  else
    printf "%-18s %s\n" "${label}:" "missing"
  fi
}

pref_contains() {
  local key="$1"
  defaults read com.apple.HIToolbox "${key}" 2>/dev/null | rg -q "${BUNDLE_ID}|${INPUT_MODE_ID}"
}

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/moyu_status.XXXXXX")"
trap 'rm -rf "${temp_dir}"' EXIT

cat > "${temp_dir}/tis_status.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

static NSString *StringForProperty(TISInputSourceRef source, CFStringRef key) {
    CFTypeRef value = TISGetInputSourceProperty(source, key);
    return value ? [(__bridge id)value description] : @"";
}

int main(void) {
    @autoreleasepool {
        NSArray *sources = CFBridgingRelease(TISCreateInputSourceList(NULL, true));
        NSInteger matches = 0;
        for (id item in sources) {
            TISInputSourceRef source = (__bridge TISInputSourceRef)item;
            NSString *sid = StringForProperty(source, kTISPropertyInputSourceID);
            NSString *bid = StringForProperty(source, kTISPropertyBundleID);
            if ([sid isEqualToString:@"com.tantan1hao.inputmethod.moyuassistant"] ||
                [sid isEqualToString:@"com.tantan1hao.inputmethod.moyuassistant.default"] ||
                [bid isEqualToString:@"com.tantan1hao.inputmethod.moyuassistant"]) {
                matches += 1;
                printf("TIS match: %s | %s\n", sid.UTF8String, bid.UTF8String);
            }
        }
        printf("TIS visible matches: %ld\n", (long)matches);
    }
    return 0;
}
EOF

clang -fobjc-arc -framework Foundation -framework Carbon "${temp_dir}/tis_status.m" -o "${temp_dir}/tis_status"
tis_output="$("${temp_dir}/tis_status")"

enabled_status="no"
selected_status="no"
if pref_contains AppleEnabledInputSources; then
  enabled_status="yes"
fi
if pref_contains AppleSelectedInputSources; then
  selected_status="yes"
fi

echo "Moyu Assistant status"
echo "---------------------"
print_presence "System install" "${SYSTEM_APP}"
print_presence "User install" "${USER_APP}"
printf "%-18s %s\n" "Enabled in prefs:" "${enabled_status}"
printf "%-18s %s\n" "Selected in prefs:" "${selected_status}"
echo "${tis_output}"
echo

if [[ -d "${SYSTEM_APP}" ]]; then
  if [[ "${selected_status}" == "yes" ]]; then
    echo "Next step: switch to 'Moyu Assistant' from the input menu, then open the app, choose a txt file, and enable Armed."
  elif [[ "${enabled_status}" == "yes" ]]; then
    echo "Next step: open System Settings -> Keyboard -> Input Sources and manually switch to 'Moyu Assistant'."
  else
    echo "Next step: open System Settings -> Keyboard -> Input Sources and add 'Moyu Assistant'. If it is missing, fully quit System Settings and reopen it. If it still does not appear, log out and log back in once."
  fi
else
  echo "Next step: build and install the system pkg first with /Users/mac/word/scripts/build_input_method_pkg.sh."
fi
