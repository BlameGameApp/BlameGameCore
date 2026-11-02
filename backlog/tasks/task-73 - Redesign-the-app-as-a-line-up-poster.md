---
id: TASK-73
title: Redesign the app as a line-up poster
status: In Progress
assignee: []
created_date: '2026-11-02 13:48'
updated_date: '2026-11-02 14:18'
labels:
  - design
milestone: m-3
dependencies: []
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the dark gradient look with a flat poster system: every player is a full-width colour band with their name justified edge to edge in a variable-width display face. No gradients, shadows, cards, pills or avatars. Includes app icon and launch screens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No gradients, shadows or rounded cards remain in lib/
- [x] #2 Every player has a distinct flat colour per room, up to the 12-player cap
- [x] #3 Names fit their band edge to edge at any length from 1 to 24 characters
- [x] #4 Round reveal is one full-colour takeover by the photo owner's band
- [x] #5 App icon and launch screens match the new palette
- [x] #6 Widget and integration tests pass
<!-- AC:END -->
