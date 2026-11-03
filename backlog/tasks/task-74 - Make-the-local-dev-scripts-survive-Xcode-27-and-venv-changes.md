---
id: TASK-74
title: Make the local dev scripts survive Xcode 27 and venv changes
status: In Progress
assignee: []
created_date: '2026-11-02 15:16'
updated_date: '2026-11-02 15:28'
labels:
  - tooling
milestone: m-4
dependencies: []
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
run-local-multiplayer.sh aborts on open -a Simulator, because Xcode 27 replaced Simulator.app with DeviceHub. uvicorn --reload also watches backend/.venv, so it restarts on changes there and wipes every in-memory room.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 run-local-multiplayer.sh gets past the simulator step on Xcode 27
- [x] #2 A change under backend/.venv does not restart the dev server
- [x] #3 A change under backend/app still restarts the dev server
- [x] #4 README describes the commands that work
<!-- AC:END -->
