"""Backend-driven round timer.

The RoundDriver owns the *timing* of a game: it announces each round, waits
`round_seconds` (or until every player has guessed), reveals the answer,
holds on the reveal so players can actually see it, advances, and finally
announces the end — emitting an event dict at each transition. The API layer
turns those events into WebSocket broadcasts.

`sleep` and `time_fn` are injected so tests can pass a no-op sleep and a
fixed clock and run instantly and deterministically. In production they're
`asyncio.sleep` and `time.time`. The round wait is a poll loop rather than
an `asyncio.Event` raced against the timeout so that it keeps using that
same injectable `sleep`.
"""

from __future__ import annotations

import asyncio
import time
from typing import Awaitable, Callable, Dict, Optional

from app.game import advance_round, current_photo, everyone_has_guessed, rankings
from app.models import Room, RoomState

EventCallback = Callable[[Dict], None]
SleepFn = Callable[[float], Awaitable[None]]
TimeFn = Callable[[], float]

# How often the driver re-checks whether everyone has guessed while waiting
# out a round. Small enough to feel responsive, large enough to not busy-loop.
_POLL_INTERVAL = 0.2

# How long the answer stays on screen before the next round starts. Without a
# pause the reveal and the next round_started land in the same tick and the
# reveal renders for zero frames -- players never learn whose photo it was.
REVEAL_SECONDS = 3.0


class RoundDriver:
    def __init__(
        self,
        room: Room,
        *,
        sleep: SleepFn = asyncio.sleep,
        time_fn: TimeFn = time.time,
        on_event: EventCallback,
    ) -> None:
        self.room = room
        self._sleep = sleep
        self._time_fn = time_fn
        self._on_event = on_event
        # The game this driver was spawned for. If the room is reset and
        # restarted while we're sleeping, the epoch moves and we bow out
        # rather than drive someone else's game.
        self._epoch = room.epoch

    def _photo_dict(self) -> Dict:
        # No owner_id: it is the answer players are about to guess, and every
        # connected client can read this frame. Same rule as _room_dict in
        # main.py -- round_revealed is the first thing that discloses it.
        photo = current_photo(self.room)
        return {"id": photo.id, "url": photo.url}

    def _standings(self) -> list:
        """Players ranked by score, highest first -- the server's ordering.

        Sent with every reveal as well as at the end so the between-rounds
        scoreboard never has to recompute or reorder scores client-side.
        """
        return [
            {"id": p.id, "name": p.name, "score": p.score, "is_host": p.is_host}
            for p in rankings(self.room)
        ]

    def _still_ours(self, round_index: Optional[int] = None) -> bool:
        """True while the room is still running the game (and round) we drive.

        Every await is a window for a REST handler to reset or restart the
        room underneath us; this is the check taken on the other side of one.
        """
        if self.room.epoch != self._epoch:
            return False
        if round_index is not None and self.room.current_round != round_index:
            return False
        return True

    async def _wait_for_round(self, round_seconds: float) -> None:
        """Wait out the round, or return early once everyone has guessed."""
        remaining = round_seconds
        while remaining > 0:
            step = min(_POLL_INTERVAL, remaining)
            await self._sleep(step)
            remaining -= step
            # Stop polling a room that was reset/restarted under us rather
            # than sitting out the rest of a round we no longer own.
            if not self._still_ours():
                return
            if everyone_has_guessed(self.room):
                return

    async def run(self) -> None:
        """Drive the game from its first round to completion."""
        while self.room.state == RoomState.IN_ROUND and self._still_ours():
            round_index = self.room.current_round
            round_seconds = self.room.round_seconds
            this_round = self.room.rounds[round_index]
            # Record the deadline on the round itself: scoring reads it so the
            # server never has to trust a client-supplied countdown.
            this_round.ends_at = self._time_fn() + round_seconds
            round_ends_at = int(this_round.ends_at * 1000)

            self._on_event(
                {
                    "type": "round_started",
                    "round_index": round_index,
                    "photo": self._photo_dict(),
                    "round_ends_at": round_ends_at,
                }
            )

            await self._wait_for_round(round_seconds)

            # The room can move while we wait (a reset, or another driver).
            # Re-read before revealing: otherwise we'd announce this round's
            # index with the *next* round's photo, and double-advance.
            if self.room.state != RoomState.IN_ROUND or not self._still_ours(round_index):
                return

            owner_id = current_photo(self.room).owner_id
            # REVEALING closes the guess window for the hold below, so a guess
            # arriving late can't be recorded against the round about to start.
            self.room.state = RoomState.REVEALING
            self._on_event(
                {
                    "type": "round_revealed",
                    "round_index": round_index,
                    "owner_id": owner_id,
                    "standings": self._standings(),
                }
            )

            await self._sleep(REVEAL_SECONDS)
            # Same re-check on the far side of the reveal hold. Without it a
            # restarted room gets advanced by the *previous* game's driver:
            # advance_round() would skip that game's first round, or raise on
            # an already-FINISHED room and kill the task.
            if not self._still_ours(round_index):
                return
            advance_round(self.room)

        # Left the loop because the room moved on without us -> not our game
        # to announce; the driver that owns it will emit its own result.
        if not self._still_ours():
            return

        # Left the IN_ROUND loop -> the game is finished.
        self._on_event({"type": "game_finished", "rankings": self._standings()})
