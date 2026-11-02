---
id: TASK-76
title: Stop a lost connection or a lost room from stranding players
status: In Progress
assignee: []
created_date: '2026-11-02 15:54'
updated_date: '2026-11-02 15:55'
labels:
  - bug
milestone: m-4
dependencies: []
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Closing a socket that is still connecting never finishes, and an outage is exactly when that happens. reconnect() stalled with the error already cleared, so the game went quiet with no banner and no more retries. A room the server no longer has was also treated as an outage, leaving players on Connection lost for good, and only the lobby reacted to being removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An outage shows the banner and runs every retry
- [x] #2 A room that no longer exists sends players home with an explanation, from any screen
- [x] #3 A failed connection no longer raises an unhandled exception
<!-- AC:END -->
