---
id: TASK-78
title: Keep CI working when the runner image changes
status: In Progress
assignee: []
created_date: '2026-11-03 08:30'
updated_date: '2026-11-03 08:30'
labels:
  - ci
dependencies: []
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ubuntu-latest moved to Ubuntu 26.04, and actions/setup-python has no 3.12.1 build for it: builds for 26.04 start at 3.12.13. Both backend jobs now fail before they run anything, which blocks every pull request, because backend/.python-version pins a patch release nothing here depends on. Name the minor version instead, as pyproject.toml already does. Nixpacks only reads the major and minor from this file, so the deployed Python doesn't change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 backend/.python-version names a minor version, so a new runner image can't strand it on a missing patch build
- [x] #2 Local pyenv still resolves the file to an installed 3.12
- [ ] #3 Backend tests and Backend build pass in CI on ubuntu-latest
<!-- AC:END -->
