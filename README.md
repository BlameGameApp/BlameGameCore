# Photo Blame

Photo Blame is a party game: everyone throws photos from their camera roll into a
room, and each round you guess whose photo is on screen — faster guesses score more.

**Website:** [photoblame.com](https://photoblame.com) · **Contact:** hello@photoblame.com

## Getting Started

Photo Blame is being built with Flutter.

### First-time setup

Native plugins (e.g. `photo_manager`) are linked with **Swift Package Manager**,
which ships with Xcode — CocoaPods is not needed. Just fetch Dart dependencies:

```sh
flutter pub get
```

### How to run

1. Start the backend (see [backend/README.md](backend/README.md)):

```sh
cd backend && uvicorn app.main:app --reload   # → http://localhost:8000
```

2. Open the iOS Simulator:

```sh
open -a Simulator
```

3. Run the app (defaults to `API_BASE=http://localhost:8000`):

```sh
flutter run
```

### Running the latest version after pulling changes

`flutter run`'s hot reload/restart does **not** pick up new native plugins or
dependency changes — you get a stale build (old data, missing features). After
switching branches or adding a dependency, do a clean rebuild:

```sh
flutter pub get           # resolve any new/changed packages
flutter clean             # drop stale build artifacts (only if things look wrong)
flutter run               # fresh build; press "q" to fully quit a running session first
```

If the simulator still shows an old build, uninstall it first:

```sh
xcrun simctl uninstall booted com.photoblame.app
```

### Local dev, hot-reload mode (backend + Backlog board + two simulators)

Photo Blame needs 2+ players to start a game. To test that on one machine,
run the app on two simulators at once — one player creates the game and shares
the code, the other joins with it. One script starts everything:

```sh
scripts/run-local-multiplayer.sh
```

This single command:

1. Starts the **backend** (`uvicorn --reload`) at `http://localhost:8000`, if
   it isn't already running.
2. Starts the **Backlog.md board** (`backlog browser`) and opens it in your
   browser, if the `backlog` CLI is on PATH.
3. Boots two simulators — `iPhone 17` and `iPhone 17 Pro` by default, override
   with `SIM_A_NAME`/`SIM_B_NAME` env vars if you don't have those — and
   installs one shared build on both.
4. Watches `lib/**/*.dart` (via `fswatch` if installed — `brew install
   fswatch` — otherwise falls back to 1s polling) and **hot-reloads both
   simulators automatically on save**.

Ctrl+C stops everything it started. This is the "hot deployment" workflow:
edit a `.dart` file, save, and both simulators pick it up within ~1s without
you re-running anything.

Individual pieces, if you want to run them separately instead:

```sh
# Backend only
cd backend && uvicorn app.main:app --reload   # → http://localhost:8000

# Backlog board only
backlog browser                               # opens the web UI

# Flutter only, with hot reload (single device, `r`/`R` in the terminal for
# manual reload/restart; edits still apply automatically once you're attached)
open -a Simulator
flutter run --dart-define=API_BASE=http://localhost:8000
```

**Manual two-simulator equivalent** (no hot reload — a fresh build per device):

```sh
xcrun simctl list devices available          # find two device UDIDs
xcrun simctl boot <udid-1>
xcrun simctl boot <udid-2>
open -a Simulator
flutter run -d <udid-1> --dart-define=API_BASE=http://localhost:8000
flutter run -d <udid-2> --dart-define=API_BASE=http://localhost:8000   # run in a second terminal
```

Each `flutter run` needs its own terminal/process — they're independent debug
sessions. Use `Cmd+Tab`/the simulator's device picker (or `xcrun simctl list
devices booted`) to switch which one is frontmost.

### Running tests

```sh
# Flutter (105 tests)
flutter test
flutter analyze                              # static analysis, run alongside tests

# Backend (162 tests)
cd backend
pytest
ruff check .                                 # pyflakes-only lint (see backend/pyproject.toml)
```

### End-to-end tests (real simulator, real backend)

`flutter test` fakes the socket, the API and the camera roll, so it cannot catch
a plugin that fails to link or a build pointed at the wrong backend. Two suites
run on real devices instead. Start the backend first.

```sh
# One device hosts a game; the second player is driven over HTTP from inside
# the test, which produces the same broadcasts a second phone would.
flutter test integration_test/app_test.dart -d "iPhone 17" \
  --dart-define=API_BASE=http://localhost:8000

# Two simulators in one room at once, both reaching the same leaderboard.
scripts/run-two-device-test.sh
```

The camera-roll picker is the one path these skip: the first photo-permission
request pops a system alert, and `WidgetTester` injects pointer events straight
into the engine rather than through the window server, so nothing in the test
can answer it. Both suites detect that, say so, and contribute the photo over
the API instead. To exercise the real picker, grant the permission by hand once
on the device and run the app normally.

## Website

`website/` is the one-page site for photoblame.com: plain HTML, nothing to build
or install. To look at it locally:

```sh
python3 -m http.server 8080 --directory website
```
