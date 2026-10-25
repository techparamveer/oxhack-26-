#!/usr/bin/env bash
# Fresh-erase Rest-overuse probe. Own simulator; does not touch Sheep-acceptance.
#
#   scripts/notif-auth-probe.sh              # 1 run
#   RUNS=5 SIM=Sheep-notif-auth scripts/notif-auth-probe.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SIM="${SIM:-Sheep-notif-auth}"
RUNS="${RUNS:-1}"
SHOTS="${SHOTS:-/tmp/sheep-notif-probe}"
DEVICE_TYPE="${DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}"
RUNTIME="${RUNTIME:-$(xcrun simctl list runtimes | awk '/iOS/ && !/unavailable/ {id=$NF} END {print id}')}"
DERIVED="${DERIVED:-.build/DerivedData}"
ONLY="SheepUITests/NotifAuthProbeUITests"
LOG="${LOG:-/tmp/sheep-notif-probe-${SIM}.log}"

if ! xcrun simctl list devices | grep -q "    $SIM ("; then
  echo "Creating simulator $SIM ($RUNTIME)"
  xcrun simctl create "$SIM" "$DEVICE_TYPE" "$RUNTIME" >/dev/null
fi

pass=0
fail=0
for i in $(seq 1 "$RUNS"); do
  echo "======== probe $i/$RUNS on $SIM ========"
  xcrun simctl shutdown "$SIM" 2>/dev/null || true
  xcrun simctl erase "$SIM"
  xcrun simctl boot "$SIM" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM" -b >/dev/null
  xcrun simctl ui "$SIM" appearance light 2>/dev/null || true
  OSLOG="/tmp/sheep-notif-oslog-$i.txt"
  xcrun simctl spawn "$SIM" log stream --level debug --predicate 'eventMessage CONTAINS "Notifications" OR eventMessage CONTAINS "Source is not authorized"' > "$OSLOG" 2>/dev/null &
  OSLOG_PID=$!
  rm -rf "$SHOTS" && mkdir -p "$SHOTS"
  RESULT="$DERIVED/notif-probe-$i.xcresult"
  rm -rf "$RESULT"
  set +e
  TEST_RUNNER_SHEEP_NOTIF_PROBE=1 TEST_RUNNER_SHEEP_SHOTS_DIR="$SHOTS" \
    xcodebuild -project Sheep.xcodeproj -scheme Sheep \
      -destination "platform=iOS Simulator,name=$SIM" \
      -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" \
      -collect-test-diagnostics never \
      -only-testing:"$ONLY" test 2>&1 \
    | tee /tmp/sheep-notif-probe-last.txt \
    | grep --line-buffered -E "error:|Test Case|failed|Executed|SUCCEEDED|FAILED|XCTAssert|\[Notifications\]|Source is not authorized"
  STATUS=${PIPESTATUS[0]}
  set -e
  if [[ "$STATUS" == "0" ]]; then
    echo "PASS $i/$RUNS"
    pass=$((pass + 1))
  else
    echo "FAIL $i/$RUNS (xcodebuild $STATUS)"
    fail=$((fail + 1))
    grep -E "Source is not authorized|add .* failed|Timed out waiting" /tmp/sheep-notif-probe-last.txt || true
  fi
  kill "$OSLOG_PID" 2>/dev/null || true
  echo "--- os_log ---"
  grep -E "Notifications|authorized" "$OSLOG" | tail -n 40 || true
  echo "$i status=$STATUS" >> "$LOG"
done

echo
echo "RESULT $pass/$RUNS passed ($fail failed) sim=$SIM"
echo "$pass/$RUNS" > "${LOG}.score"
exit $(( fail > 0 ? 1 : 0 ))
