#!/usr/bin/env bash
# End-to-end acceptance run: walks the MVP_PLAN demo script offline in the Simulator
# (SheepUITests/DemoScriptUITests) and saves a numbered screenshot of every step.
#
#   scripts/acceptance.sh                 # own simulator "Sheep-acceptance", shots in /tmp/sheep-acceptance
#   SIM=MySim SHOTS=~/Desktop/shots scripts/acceptance.sh
#   ONLY=SheepUITests/DemoScriptUITests/test2_DarkModeScreens scripts/acceptance.sh
#   FRESH=1 scripts/acceptance.sh         # erase the simulator first (exercises the first-launch prompts)
set -euo pipefail

cd "$(dirname "$0")/.."
SIM="${SIM:-Sheep-acceptance}"
SHOTS="${SHOTS:-/tmp/sheep-acceptance}"
ONLY="${ONLY:-SheepUITests}"
DEVICE_TYPE="${DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}"
RUNTIME="${RUNTIME:-$(xcrun simctl list runtimes | awk '/iOS/ && !/unavailable/ {id=$NF} END {print id}')}"
DERIVED="${DERIVED:-.build/DerivedData}"

if ! xcrun simctl list devices | grep -q "    $SIM ("; then
  echo "Creating simulator $SIM ($RUNTIME)"
  xcrun simctl create "$SIM" "$DEVICE_TYPE" "$RUNTIME" >/dev/null
fi
if [[ "${FRESH:-0}" == "1" ]]; then
  echo "Erasing $SIM (fresh install: notification prompt, keyboard tips)"
  xcrun simctl shutdown "$SIM" 2>/dev/null || true
  xcrun simctl erase "$SIM"
fi
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null

# Notifications can't be pre-granted with `simctl privacy`; the test taps "Allow" on the alert.
# Clean light appearance so screenshots are comparable run to run (the dark pass uses a launch hook).
xcrun simctl ui "$SIM" appearance light 2>/dev/null || true
xcrun simctl status_bar "$SIM" override --batteryState charged --batteryLevel 100 2>/dev/null || true

rm -rf "$SHOTS" && mkdir -p "$SHOTS"
RESULT="$DERIVED/acceptance-$(date +%Y%m%d-%H%M%S).xcresult"

set +e
TEST_RUNNER_SHEEP_ACCEPTANCE=1 TEST_RUNNER_SHEEP_SHOTS_DIR="$SHOTS" \
  xcodebuild -project Sheep.xcodeproj -scheme Sheep \
    -destination "platform=iOS Simulator,name=$SIM" \
    -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" \
    -collect-test-diagnostics never \
    -only-testing:"$ONLY" test 2>&1 \
  | grep --line-buffered -E "error:|Test Case|failed|Executed|SUCCEEDED|FAILED|XCTAssert|\[acceptance\]" \
  | grep --line-buffered -v "IDELaunchParametersSnapshot"
STATUS=${PIPESTATUS[0]}
set -e

echo
echo "Screenshots: $SHOTS"
ls -1 "$SHOTS" 2>/dev/null || true
echo "Result bundle: $RESULT"
exit "$STATUS"
