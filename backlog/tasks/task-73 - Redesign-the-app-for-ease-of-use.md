---
id: TASK-73
title: Redesign the app for ease of use
status: In Progress
assignee: []
created_date: '2026-11-02 13:48'
updated_date: '2026-11-02 15:55'
labels:
  - design
milestone: m-3
dependencies: []
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Replace the dark gradient look with a calm, flat interface built on standard controls. A first pass as a wood-type poster was dropped: stretched names were too slow to read under a countdown. Every screen now has one obvious next step, a round keeps everything in place, and leaving is confirmed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every player has a distinct flat colour per room, up to the 12-player cap
- [x] #2 App icon and launch screens match the new palette
- [x] #3 Widget and integration tests pass
- [x] #4 Every screen has one obvious next action, and names stay readable under a countdown
- [x] #5 Leaving is confirmed, including a swipe back
- [x] #6 A full room of long names fits the smallest iPhone and large text
- [x] #7 No gradients remain in lib/
- [x] #8 A playful layer sits on top of the controls, with no emoji or gradients
<!-- AC:END -->
