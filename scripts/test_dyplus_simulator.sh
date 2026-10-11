#!/bin/zsh
# Build actual settings/core code for an isolated simulator app, never inject into Aweme.
set -euo pipefail
cd "${0:A:h:h}"
dyplus_output=$(mktemp -d /private/tmp/dyplus-regression.XXXXXX)
dyplus_bundle="$dyplus_output/DYPlusPreview.app"
mkdir -p "$dyplus_bundle"
cp tests/DYPlus/DYPlusPreviewInfo.plist "$dyplus_bundle/Info.plist"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator \
  -fobjc-arc -Wall -Werror -DDYPLUS_RELEASE_BUILD=1 -Wno-deprecated-declarations -Wno-incomplete-implementation \
  -Wno-objc-protocol-method-implementation -Wno-protocol \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework Photos -framework ImageIO \
  -I Sources/DYPlus \
  tests/DYPlus/DYPlusPreviewMain.m tests/DYPlus/DYPlusPreviewHostStubs.m tests/DYPlus/DYPlusCoreRegression.m tests/DYPlus/DYPlusCrashRetentionRegression.m tests/DYPlus/DYPlusRemoteHandlerRegression.m Sources/DYPlus/Settings/*.m \
  Sources/DYPlus/Core/Runtime/DYPlusRuntime.m Sources/DYPlus/Core/UI/DYPlusColorParser.m Sources/DYPlus/Core/Network/DYPlusRemoteConfiguration.m Sources/DYPlus/Core/Storage/DYPlusSettingsArchive.m Sources/DYPlus/Core/Configuration/DYPlusConfigurationCache.m \
  Sources/DYPlus/Core/Utilities/DYPlusUtils.m Sources/DYPlus/Core/Configuration/DYPlusUtilsConfig.m Sources/DYPlus/Core/UI/DYPlusUtilsTraversal.m \
  Sources/DYPlus/Core/UI/DYPlusTheme.m Sources/DYPlus/Core/Storage/DYPlusPaths.m Sources/DYPlus/Services/Preferences/DYPlusSwitchManager.m \
  Sources/DYPlus/Core/UI/DYPlusUIContext.m \
  Sources/DYPlus/Core/Network/DYPlusDownloadResponse.m \
  Sources/DYPlus/Diagnostics/DYPlusCrashCatcher.m \
  -o "$dyplus_bundle/DYPlusPreview" > "$dyplus_output/build.log" 2>&1 || { sed -n '1,160p' "$dyplus_output/build.log"; exit 1; }
printf 'Preview bundle: %s\n' "$dyplus_bundle"
if (( $# > 0 )); then
  xcrun simctl install "$1" "$dyplus_bundle"
  xcrun simctl launch --terminate-running-process --console "$1" com.xiaolegun.dyplus.settings-preview test > "$dyplus_output/tests.log" 2>&1
  sed -n '/CORE SUMMARY/p' "$dyplus_output/tests.log"
  sed -n '/UI SUMMARY/p' "$dyplus_output/tests.log"
  sed -n '/REMOTE HANDLERS/p' "$dyplus_output/tests.log"
  if ! grep -q 'CORE SUMMARY: .* PASS, 0 FAIL' "$dyplus_output/tests.log"; then
    tail -n 80 "$dyplus_output/tests.log"
    exit 1
  fi
  if ! grep -q 'REMOTE HANDLERS: 6 PASS, 0 FAIL' "$dyplus_output/tests.log"; then
    tail -n 80 "$dyplus_output/tests.log"
    exit 1
  fi
  printf 'Test log: %s\n' "$dyplus_output/tests.log"
  xcrun simctl launch --terminate-running-process --console "$1" com.xiaolegun.dyplus.settings-preview seed-retention > "$dyplus_output/retention-seed.log" 2>&1
  xcrun simctl launch --terminate-running-process --console "$1" com.xiaolegun.dyplus.settings-preview verify-retention > "$dyplus_output/retention-test.log" 2>&1
  if ! grep -q 'CRASH RETENTION: PASS' "$dyplus_output/retention-test.log"; then
    tail -n 80 "$dyplus_output/retention-test.log"
    exit 1
  fi
  printf 'Crash retention: PASS\n'
fi
