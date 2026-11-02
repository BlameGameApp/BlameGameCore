---
id: TASK-75
title: Keep room codes from spelling words
status: In Progress
assignee: []
created_date: '2026-11-02 15:16'
updated_date: '2026-11-02 15:17'
labels:
  - backend
milestone: m-3
dependencies: []
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Room codes are drawn from an alphabet with vowels, so they can spell words, including offensive ones, and the code is the largest thing in the lobby.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Generated codes contain no vowels
- [x] #2 Generated codes contain no digit that reads as a vowel
- [x] #3 Existing code length and uniqueness are unchanged
<!-- AC:END -->
