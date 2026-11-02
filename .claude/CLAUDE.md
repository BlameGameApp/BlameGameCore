# Photo Blame — Project Knowledge

A party game: players join a room, contribute random photos from their camera roll,
then guess *whose* photo each round shows. Points are awarded for correct + fast
guesses; rounds tally into a final leaderboard.

## Stack

- **Frontend:** Flutter (Dart SDK `^3.11.5`), Material 3. Code in `lib/`.
- **Backend:** FastAPI (Python 3.12), in-memory state + WebSockets. Code in `backend/app/`.
- **Deploy:** backend targets Railway (`backend/railway.json`; the start command lives there, there is no Procfile). Single replica.

## Architecture

### Flutter (`lib/`)
Layered: `config → models → services → state → screens`, with `theme/` and
`ui/` holding presentation shared across screens.
- `config.dart` — `apiBase` from `String.fromEnvironment('API_BASE')`; `wsBase` derived by swapping `http`→`ws`. The **default is build-mode dependent**: localhost in debug/profile so `flutter run` just works, and **empty in release**, because an IPA quietly aimed at the device's own loopback fails every call with nothing to diagnose it by (and iOS ATS blocks cleartext HTTP regardless). `apiBaseProblem` turns that, and any non-https release base, into a "Not configured" screen at startup instead of a spinner. A release build must carry `--dart-define=API_BASE=https://…`.
- `models/game_models.dart` — `GamePlayer`, `PhotoInfo`, and a sealed `GameEvent` hierarchy (deserialize-only). **Pure Dart, no Flutter import** — per-player colours/avatars live in `ui/player_cosmetics.dart` instead, derived from a platform-stable hash (`String.hashCode` differs between the VM and dart2js, so the same player looked different on iOS and web).
- `services/api_client.dart` — thin `http` REST wrapper; injectable `http.Client` for tests.
- `services/game_socket.dart` — `web_socket_channel`, exposes `Stream<GameEvent>`. A `GameSocketFactory` typedef is injected into the controller so tests can drive state with a fake socket.
- `state/game_controller.dart` — `ChangeNotifier` (no Provider/Riverpod/Bloc). One instance is created in `HomeScreen`, passed by constructor down through Lobby → Game → Results, and **disposed by `HomeScreen` when the pushed route returns** (it awaits the `push`) — otherwise every game leaks a live WebSocket. Identity lives in a non-nullable `GameSession` created at join time, so there are no `roomCode!` force-unwraps and a half-joined controller is unrepresentable. `connectionError` + `reconnect()` surface a dropped socket rather than freezing the game, and a 404 on reconnect ends it, because the room is gone and no retry can bring it back. `GameControllerScreen.leaveIfRemoved` is what takes a player home from any screen.
- `theme/app_theme.dart` — `buildAppTheme()` plus an `AppColors` `ThemeExtension`; read it via `context.colors`.
- `ui/` — cross-screen presentation: `player_cosmetics.dart`, `result_banner.dart`, `connection_banner.dart`, `snack.dart`, `error_text.dart` (`friendlyError` unwraps the backend's `{"detail": ...}` so raw JSON never reaches a player), and:
  - `controller_screen.dart` — the `GameControllerScreen` mixin every controller-driven screen uses. It owns the listener wiring, the `mounted` guard (the callback fires from the WebSocket stream, so `Navigator.of(context)` can throw) and `navigateOnce`, which latches route pushes so an event burst can't push the same screen twice. Each of those was hand-rolled in three screens; TASK-46 was the latch going wrong.
  - `tinted_card.dart` — paints its fill through a **`Material`**, not a `BoxDecoration`. Ink splashes and `ListTile` backgrounds are drawn on the nearest `Material` ancestor, so a decorated box over it swallows them — and Flutter asserts on exactly that arrangement.
- `screens/` — `home`, `lobby`, `game`, `results`.
- `main.dart` — `PhotoBlameApp`, plus the misconfigured-build screen `config.dart` gates on.

### Backend (`backend/app/`)
Pure logic under thin I/O layers:
- `game.py`, `scoring.py` — pure game rules + scoring (well unit-tested).
- `models.py` — the `Player` / `Photo` / `Round` / `Room` dataclasses and the `RoomState` enum everything else operates on.
- `photo_meta.py` — strips EXIF (and with it GPS), XMP and PNG text chunks from uploads. Structural: it walks JPEG segment and PNG chunk headers and drops the metadata ones, so there is no decode, no re-encode and no image library in the trust path for attacker-supplied bytes. **The server owns this guarantee, not the client** — the iOS client's re-encode drops EXIF as a side effect, but Android/web/curl would not.
- `main.py` — FastAPI routes (REST + one WS route `/ws/{code}/{player_id}`).
- `store.py` — process-wide in-memory `GameStore` singleton (`dict[code→Room]`). **State is lost on restart and can't be shared across replicas.** Rooms carry `last_active` and are evicted after `ROOM_TTL_SECONDS` (6h) idle by a **lazy sweep on create/lookup** — no background task, since only a request can grow the store. Capped at `MAX_ROOMS` (500), swept first so an expired store doesn't read as a flood; past it `POST /rooms` is a 503. `POST /rooms` is unauthenticated and every room is in RAM, so without the cap a create loop kills the container and takes every live game with it. `time_fn`/`on_evict` are injectable; `main.py` wires `on_evict` to delete `uploads/{code}/`, refusing any code that resolves outside `UPLOAD_DIR`. `DELETE /rooms/{code}?host_id=` ends a room explicitly.
- `connection.py` — `ConnectionManager`, broadcasts events to a room's sockets.
- `timer.py` — `RoundDriver` drives round timing (sleep injectable for tests). It holds on the reveal for `REVEAL_SECONDS` before advancing; without that pause `round_revealed` and the next `round_started` land in the same tick and players never see whose photo it was. It re-checks the room before revealing, so a round that moved underneath it isn't announced with the wrong photo.
- Photos are written to local disk under `uploads/{code}/` (ephemeral on Railway).

## Commands

### Flutter
```sh
flutter pub get
flutter analyze
flutter test                     # currently 105 tests
flutter run                      # needs a simulator/device

# On a real simulator, against a real backend (start it first):
flutter test integration_test/app_test.dart -d "iPhone 17" \
  --dart-define=API_BASE=http://localhost:8000
scripts/run-two-device-test.sh   # two simulators in one room at once
```
`test/` fakes the socket, the API client and the camera roll, so it cannot catch
a plugin that does not link or a build pointed at the wrong backend;
`integration_test/` is what covers those. Neither can exercise the camera-roll
picker: the first permission request pops a system alert, `WidgetTester` injects
pointer events straight into the engine rather than through the window server,
and a pre-granted TCC decision does not survive the reinstall `flutter test`
performs. Both suites detect that and contribute the photo over the API instead.

### Backend
```sh
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
pytest                           # currently 175 tests
ruff check .                     # pyflakes (F) only; configured in backend/pyproject.toml
```

### Branding / app icon
Every launcher icon is generated — never hand-edit the PNGs, regenerate them.
```sh
./scripts/generate-app-icons.sh   # iOS, Android (legacy + adaptive) and web, from the SVGs
```
- `assets/branding/app_icon.svg` is the source of truth. `logo_mark.svg` is the mark
  with no background; `app_icon_foreground.svg` / `app_icon_background.svg` are the two
  Android adaptive layers, the foreground inset to the 66% zone launchers mask to.
- `scripts/rasterize-svg.swift` does the rasterizing. It exists because **AppKit is the
  only SVG decoder on macOS** — ImageIO reports no SVG type at all — and because `sips`
  can render the SVG but always writes an alpha channel, which the iOS AppIcon set is
  not allowed to have. Drawing through an explicit `CGContext` is what makes the iOS
  PNGs opaque without a lossy JPEG round-trip.
- `logo_mark.png` (+ `2.0x/`, `3.0x/`) is generated too — the home screen shows the mark,
  and Flutter cannot render SVG without a package.
- Colours come from `AppColors.dark` only. The icon is three photo cards fanned like a
  hand, on a brand-red sunburst, under sixty pieces of confetti. Two consequences:
  **red is not in the confetti palette** (a red chip on a red sunburst is invisible —
  the pieces are teal, gold, white and a dark navy), and `logo_mark.svg` keeps only the
  largest dozen pieces, because sixty is texture at 1024px and mush at the 96px the
  home screen draws the mark at.
- The **launch screens** are generated by the same script. They are drawn by the OS
  before any Dart runs, so they cannot read `AppColors`: the iOS storyboard and
  `android/app/src/main/res/values/colors.xml` each hardcode `bgTop` (`#1A1A2E`) and
  have to be kept in step with `app_theme.dart` by hand. Both were the untouched
  Flutter default — a white ground behind a 1x1 transparent image — so every cold
  start flashed white before the dark UI appeared.

## iOS release checklist (what TestFlight needs)

- `ios/Runner/PrivacyInfo.xcprivacy` declares what the app collects (photos, the
  display name — both unlinked, neither tracking). `Flutter.framework` and
  `photo_manager` ship their own manifests for the required-reason APIs they call,
  and Apple aggregates all three, which is why the app's own
  `NSPrivacyAccessedAPITypes` is deliberately empty.
- `ITSAppUsesNonExemptEncryption` is `false` in `Info.plist` (HTTPS only, which is
  exempt). Without it every upload stops to ask for export compliance by hand.
- A release build **must** carry `--dart-define=API_BASE=https://…`; see `config.dart`.

## Tickets / Backlog

Work is tracked with **Backlog.md** in `backlog/`. Tasks are grouped under milestones
(Core Gameplay, Accounts & Social, Infrastructure & Persistence, Gameplay Polish,
Testing & Quality) with dependency links.

```sh
backlog task list --plain
backlog board
backlog browser                  # web UI
```

## Working conventions (IMPORTANT)

- **One ticket = one PR.** Each Backlog task is implemented on its own branch
  (`feature/task-<id>-<slug>`) and opened as a separate pull request. Never bundle
  multiple tickets into one branch/PR.
- **Spawn a subagent per ticket when it fits.** For tickets that are self-contained
  units of work (most of them), dispatch a subagent to implement it — use an isolated
  **worktree** so parallel tickets don't collide. Keep small/trivial changes inline.
- Mark the ticket `In Progress` when starting and check off acceptance criteria as they
  land (`backlog task edit <id> -s "In Progress" --check-ac <n>`).
- **Never push to git without being asked** (also a global rule). Commit on the feature
  branch; open the PR only when the user requests it.
- Branch feature work off `main`, not off another in-flight feature branch.

## Game rules that are enforced server-side (don't re-litigate client-side)

- **Scoring timing is the server's.** The round's deadline lives on `Round.ends_at`
  (set by the `RoundDriver`); `submit_guess` derives `seconds_left` from it. The client
  sends only `round_index`, never a countdown — it used to send `seconds_left`, and
  posting `99999` was worth ~10M points.
- **Guesses carry their round.** A guess in flight across a round boundary is rejected
  rather than recorded against the round the player never saw (which also used to
  consume their guess slot for the new round).
- **Starting needs photos from 2+ distinct players**, or every round shows one person's
  pictures and they win by recognising all of them. The lobby mirrors this in
  `GameController.canStart` and shows real per-player readiness from `photo_count`.
- Uploads are capped (8 MB, 10 per player, JPEG/PNG magic bytes checked, lobby only);
  rooms cap at 12 players; names are 1–24 chars.

## Style

Prefer the simplest solution that actually works: reuse what's already in the codebase,
stdlib/native before new dependencies, no abstractions or config that aren't needed yet.
Don't simplify away input validation at trust boundaries, error handling, or security.

## Local iOS dev — known gotchas (learned the hard way)

- **iOS plugins are linked with Swift Package Manager, not CocoaPods.** CocoaPods was
  deintegrated once every plugin became a Swift Package; there is no `ios/Podfile` and
  `brew install cocoapods` is not part of setup. TASK-25 left the Xcode project half
  deintegrated — a tracked `Podfile`, `Pods-*.xcconfig` base configurations on the
  RunnerTests target and two `[CP] Check Pods Manifest.lock` phases that fail the
  build when `ios/Pods` is absent — so a fresh clone could not build iOS. All of it is
  gone now; if any of it comes back, something re-ran `pod install`. Plugins are statically linked into
  `Runner.debug.dylib` rather than embedded under `Runner.app/Frameworks/`, so check
  there (`nm Runner.app/Runner.debug.dylib | grep -i <plugin>`) when verifying a plugin
  is linked — the top-level `Runner` binary is just a thin launcher stub.
- **Never run two `flutter run`s against this project concurrently.** They share
  `build/ios` and race while copying `Flutter.framework`, failing one with
  `rsync`/`move_file: Flutter.framework/Flutter: No such file or directory`. Build once
  (`flutter build ios --simulator --debug`) and launch each device with
  `--use-application-binary=build/ios/iphonesimulator/Runner.app`, as
  `scripts/run-local-multiplayer.sh` does.
- **A stale app on the simulator looks exactly like "my change didn't work."** Symptoms:
  buttons don't do anything, UI shows data/copy that doesn't exist anywhere in `lib/`,
  and the backend log shows zero incoming requests. Confirm which build is actually
  running before debugging app logic — check `ps`/`pgrep -fl "flutter run"` for a live
  session, and grep `lib/` for suspicious UI text before assuming it's a code bug.
  Fix: fully quit (`q` in the `flutter run` terminal, not hot reload/restart — new native
  plugins need a real rebuild), and if needed `xcrun simctl uninstall booted <bundle-id>`
  first, then relaunch clean.
- **A subagent's "done, verified" claim needs re-checking when the agent couldn't run the
  toolchain.** One subagent guessed a `photo_manager` API name
  (`requestPermissionExtended`) that didn't exist (real method: `requestPermissionExtend`)
  because it had no `flutter`/`dart` on PATH to catch it. `flutter analyze` caught it in
  under 2 seconds once run for real. Always run analyze/test yourself against actual
  installed package sources before merging subagent-written code that touches an external
  API surface.
- **Local multiplayer testing** needs 2+ players; use `scripts/run-local-multiplayer.sh`
  to boot two simulators + backend + Backlog board in one shot rather than juggling
  multiple manual `flutter run` sessions by hand.
