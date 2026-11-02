#!/usr/bin/env bash
# Brings up the window that shows the booted simulators.
#
# Xcode 27 replaced Simulator.app with DeviceHub, which sits inside Xcode.app
# where LaunchServices can't find it by name, so `open -a Simulator` fails
# there. Booted simulators run fine without a window, so a missing app is a
# warning rather than a failure: this must never abort a script that calls it.
if open -a Simulator 2>/dev/null; then
  exit 0
fi

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if open -a "${developer_dir%/Developer}/Applications/DeviceHub.app" 2>/dev/null; then
  exit 0
fi

echo "Found neither Simulator nor DeviceHub; simulators keep running without a window." >&2
