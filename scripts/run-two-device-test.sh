#!/usr/bin/env bash
# Runs integration_test/two_device_test.dart on two simulators at once, so the
# app is actually tested against another copy of itself.
#
# Usage:
#   scripts/run-two-device-test.sh            # boots and uses the defaults
#
# The room is created here rather than by one of the devices: there is no way
# for the first device to tell the second which code it drew, so the code is
# handed to both as a --dart-define.
#
# The two runs are staggered. Both build into build/ios, and two concurrent
# builds race while copying Flutter.framework — the same failure the local
# multiplayer script works around. Starting the second run once the first has
# finished building makes its build a cache hit.
set -euo pipefail

cd "$(dirname "$0")/.."

API_BASE="${API_BASE:-http://localhost:8000}"
SIM_A_NAME="${SIM_A_NAME:-iPhone 17}"
SIM_B_NAME="${SIM_B_NAME:-iPhone 17 Pro}"

device_id() {
  xcrun simctl list devices available \
    | grep -E "^ +$1 \(" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/'
}

A="$(device_id "$SIM_A_NAME")"
B="$(device_id "$SIM_B_NAME")"
[ -n "$A" ] && [ -n "$B" ] || { echo "could not find both simulators" >&2; exit 1; }

for d in "$A" "$B"; do xcrun simctl boot "$d" 2>/dev/null || true; done
scripts/open-simulator.sh

curl -sf "$API_BASE/health" > /dev/null || {
  echo "backend not reachable at $API_BASE — start it first" >&2; exit 1; }

CODE="$(curl -sf -X POST "$API_BASE/rooms" | sed -E 's/.*"code":"([^"]+)".*/\1/')"
[ -n "$CODE" ] || { echo "could not create a room" >&2; exit 1; }
echo "room: $CODE"

run_on() {
  flutter test integration_test/two_device_test.dart \
    -d "$1" \
    --dart-define="API_BASE=$API_BASE" \
    --dart-define="ROOM_CODE=$CODE" \
    --dart-define="PLAYER_NAME=$2"
}

echo "==> $SIM_A_NAME as Alice"
run_on "$A" Alice > /tmp/two-device-a.log 2>&1 &
A_PID=$!

# Wait for the first build to finish before starting the second.
for _ in $(seq 1 120); do
  grep -q "Xcode build done" /tmp/two-device-a.log 2>/dev/null && break
  sleep 1
done

echo "==> $SIM_B_NAME as Bob"
run_on "$B" Bob > /tmp/two-device-b.log 2>&1 &
B_PID=$!

status=0
wait "$A_PID" || status=1
wait "$B_PID" || status=1

echo
echo "--- $SIM_A_NAME (Alice) ---"; tail -6 /tmp/two-device-a.log
echo "--- $SIM_B_NAME (Bob) ---";   tail -6 /tmp/two-device-b.log
exit "$status"
