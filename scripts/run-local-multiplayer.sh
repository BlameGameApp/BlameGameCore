#!/usr/bin/env bash
# One-shot local dev setup: starts the backend, the Backlog.md board, and two
# iOS simulators running the app, so you can test multiplayer (create on one,
# join on the other) without a physical second device.
#
# Usage:
#   scripts/run-local-multiplayer.sh
#
# Requires: Xcode simulators, Flutter, a backend/.venv with deps installed, and
# (optionally) the `backlog` CLI.
set -euo pipefail

cd "$(dirname "$0")/.."

API_BASE="${API_BASE:-http://localhost:8000}"
BACKLOG_PORT="${BACKLOG_PORT:-6420}"
SIM_A_NAME="${SIM_A_NAME:-iPhone 17}"
SIM_B_NAME="${SIM_B_NAME:-iPhone 17 Pro}"

PIDS=()
cleanup() {
  echo
  echo "Shutting down..."
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup INT TERM EXIT

# --- backend -----------------------------------------------------------
if curl -sf "$API_BASE/health" > /dev/null 2>&1; then
  echo "Backend already running at $API_BASE"
else
  echo "Starting backend..."
  # --reload-dir: left to itself --reload also watches .venv, and any change
  # there restarts the server and wipes every room, since they live in memory.
  (cd backend && source .venv/bin/activate && uvicorn app.main:app --reload --reload-dir app --host 0.0.0.0 --port 8000) &
  PIDS+=("$!")
  for _ in $(seq 1 30); do
    curl -sf "$API_BASE/health" > /dev/null 2>&1 && break
    sleep 1
  done
  curl -sf "$API_BASE/health" > /dev/null 2>&1 || { echo "Backend failed to start" >&2; exit 1; }
  echo "Backend up at $API_BASE"
fi

# --- backlog board -------------------------------------------------------
# The board is a tool with its own lifetime, not part of this session, so it is
# started detached and deliberately NOT added to PIDS.
#
# It used to be a child of this script. The trap below then killed it on exit
# while the tab opened three lines earlier stayed open — and the Backlog.md
# frontend reconnects to its websocket on a timer forever rather than showing an
# error, so the board looked like a page that never finished loading.
if curl -sf "http://127.0.0.1:$BACKLOG_PORT/api/config" > /dev/null 2>&1; then
  echo "Backlog.md board already running at http://127.0.0.1:$BACKLOG_PORT"
  open "http://127.0.0.1:$BACKLOG_PORT" || true
elif command -v backlog > /dev/null 2>&1; then
  echo "Starting Backlog.md board on port $BACKLOG_PORT..."
  # --non-interactive because a backgrounded process has no terminal to answer
  # the "port in use, try another?" prompt with.
  nohup backlog browser --port "$BACKLOG_PORT" --no-open --non-interactive \
    > /tmp/photoblame-backlog-board.log 2>&1 &
  BOARD_PID=$!
  disown "$BOARD_PID" 2>/dev/null || true
  for _ in $(seq 1 20); do
    curl -sf "http://127.0.0.1:$BACKLOG_PORT/api/config" > /dev/null 2>&1 && break
    sleep 0.5
  done
  if curl -sf "http://127.0.0.1:$BACKLOG_PORT/api/config" > /dev/null 2>&1; then
    echo "Board up at http://127.0.0.1:$BACKLOG_PORT"
    echo "  it outlives this script — 'kill $BOARD_PID' to stop it"
    open "http://127.0.0.1:$BACKLOG_PORT" || true
  else
    echo "Board did not come up; see /tmp/photoblame-backlog-board.log" >&2
  fi
else
  echo "Skipping Backlog.md board: 'backlog' CLI not on PATH (npm i -g backlog.md)."
fi

# --- simulators ----------------------------------------------------------
boot_by_name() {
  local name="$1"
  local udid
  udid=$(xcrun simctl list devices available | grep -F "$name (" | grep -v "Pro Max" | head -1 | sed -E 's/.*\(([-A-F0-9]+)\).*/\1/')
  if [ -z "$udid" ]; then
    echo "No simulator named '$name' found. Edit SIM_A_NAME/SIM_B_NAME or create one in Xcode." >&2
    exit 1
  fi
  xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1 || xcrun simctl boot "$udid" > /dev/null 2>&1 || true
  echo "$udid"
}

UDID_A=$(boot_by_name "$SIM_A_NAME")
UDID_B=$(boot_by_name "$SIM_B_NAME")

echo "Player 1 -> $SIM_A_NAME ($UDID_A)"
echo "Player 2 -> $SIM_B_NAME ($UDID_B)"
echo "API_BASE=$API_BASE"
echo

scripts/open-simulator.sh

# Build once up front and reuse the binary on both simulators. Two concurrent
# `flutter run`s share build/ios and race while copying Flutter.framework, which
# fails one of them with rsync/"move_file: ... No such file or directory".
APP_PATH="build/ios/iphonesimulator/Runner.app"
echo "Building the iOS simulator app once (shared by both simulators)..."
flutter build ios --simulator --debug --dart-define=API_BASE="$API_BASE"

# API_BASE is compiled into the binary above, so --use-application-binary runs
# take no --dart-define (it would be ignored: these skip the build step).
flutter run -d "$UDID_A" --use-application-binary="$APP_PATH" &
PIDS+=("$!")
flutter run -d "$UDID_B" --use-application-binary="$APP_PATH" &
PIDS+=("$!")

wait
