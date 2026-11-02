# Photo Blame backend

FastAPI backend for the Photo Blame game: rooms, players, photo upload, and a
backend-driven round timer. State is held **in memory** (no database) and live
updates are pushed over **WebSockets**.

## Run locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"     # installs runtime + test deps
pytest                       # no server needed
uvicorn app.main:app --reload --reload-dir app
# → http://127.0.0.1:8000/docs
```

## Deploy to Railway

This directory is Railway-ready:

- `railway.json` — Nixpacks build + start command
  (`uvicorn app.main:app --host 0.0.0.0 --port $PORT`), pinned to **1 replica**,
  with a `/health` healthcheck that gates each deploy.
- `.python-version` — Python 3.12.

### One-time setup (manual, in the Railway dashboard)

Deploys are driven by **Railway's own GitHub integration**, not by CI. Railway
watches `main` and rebuilds only when the backend changes, so a Flutter-only or
docs-only merge leaves the running server alone. That matters here: game state
is in memory, so every redeploy drops all live rooms.

1. Create a project, then **Deploy from GitHub repo** and pick this repository.
2. **Settings → Root Directory** → `backend`. The integration checks out the
   whole repo, so the service has to be told which folder to build.
3. **Settings → Watch patterns** → `/backend/**`. This is what stops unrelated
   merges from redeploying. Paths are relative to the repo root, not to the
   root directory.
4. **Settings → Networking → Generate Domain** to get a public URL, e.g.
   `https://<app>.up.railway.app`.
5. **Variables**: `UPLOAD_DIR` is optional — it defaults to `uploads`, which
   works out of the box. Only set it if you attach a Volume (see below).
   `PORT` is injected by Railway; do not set it yourself.
6. Deploy. Railway installs `[project].dependencies` from `pyproject.toml`
   (the `dev` extras are skipped in production).
7. Verify: `curl https://<app>.up.railway.app/health` → `{"status":"ok"}`.

> **Do not also deploy from GitHub Actions.** The two would race and deploy the
> same commit twice. The workflow deliberately has no deploy job.

### Deploying by hand

`railway up` still works for a one-off deploy from your machine:

```bash
cd backend && railway link && railway up
```

Two gotchas, both of which have cost real debugging time:

- It uploads the *contents* of `backend/` as the build root, so inside the
  archive the paths are `app/main.py`, not `backend/app/main.py`. A
  `/backend/**` watch pattern therefore matches nothing and the deploy is
  silently marked **Skipped** — no build, no error. Watch patterns only work
  for the GitHub integration.
- The CLI must be v5 or newer (`npm install -g @railway/cli`). The Homebrew
  formula is pinned to v2, whose auth endpoint no longer exists, so
  `railway login` fails there with a bare `404`.

### Important constraints (by design)

- **Single instance only.** Game state lives in RAM, so it cannot be shared
  across replicas — keep `numReplicas: 1`. Do not enable horizontal scaling.
- **Ephemeral storage.** Railway's filesystem resets on each redeploy, so
  uploaded photos and in-progress games are lost on deploy. Acceptable for
  short-lived party games. (For persistence later: attach a Railway Volume and
  point `UPLOAD_DIR` at it, plus a real store for game state.)
- **CORS is open** (`allow_origins=["*"]`) so the Flutter web/mobile client can
  call it from any origin. No cookies or `Authorization` headers are used, and
  `allow_credentials` is off, so an open origin list grants nothing.
- **Rooms are capped** at `MAX_ROOMS` (see `app/store.py`) and creation is
  refused with a 503 past that. `POST /rooms` is unauthenticated and every room
  lives in this process's memory, so without a ceiling a create loop kills the
  container and takes every live game with it.

## How player photos are handled

This is the part with real privacy consequences, so the model is written down
rather than left to be inferred:

- **Access is by unguessable URL.** A photo lives at
  `/rooms/<code>/photos/<12 hex chars>.<ext>` and that endpoint is not
  authenticated — anyone holding the URL can fetch it. That is deliberate: the
  URL is only ever handed to players of that room, over their own authenticated
  WebSocket, and `Image.network` has no way to send a credential. Treat the URL
  itself as the secret.
- **Metadata is stripped on upload.** EXIF (and with it GPS coordinates), XMP
  and PNG text chunks are removed before the bytes touch disk — see
  `app/photo_meta.py`. The iOS client also happens to re-encode and drop EXIF,
  but that is one client on one platform; the server holds the guarantee for
  every caller.
- **Retention is the room's lifetime.** `uploads/<code>/` is deleted when the
  room is deleted or swept for inactivity (6h), and Railway's filesystem is
  ephemeral anyway, so a redeploy clears everything. Nothing is backed up and
  no photo outlives its game.
- **Uploads are bounded**: 8 MB per file, 10 per player, JPEG/PNG confirmed by
  magic bytes rather than the client's `Content-Type`, and lobby-only.

## Pointing the Flutter app at this backend

The Flutter app reads its base URL from a compile-time define:

```bash
# Local backend
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000

# Deployed Railway backend
flutter run -d chrome --dart-define=API_BASE=https://<app>.up.railway.app
```

The app derives the WebSocket URL automatically (`http`→`ws`, `https`→`wss`).
