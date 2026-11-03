"""Tests for the backend round timer (app/timer.py).

The RoundDriver runs a game's rounds over time. To keep tests instant, the
driver takes an injectable async `sleep` — tests pass a no-op so no real
waiting happens. We assert the *sequence* of events it emits and that the room
state machine advances correctly.

Run async tests via anyio's pytest plugin (installed with FastAPI). The
`anyio_backend` fixture pins it to asyncio.
"""

import pytest

from app.game import Room, add_player, add_photo, reset_room, start_game
from app.models import RoomState
from app.timer import REVEAL_SECONDS, RoundDriver


@pytest.fixture
def anyio_backend():
    return "asyncio"


async def _noop_sleep(_seconds: float) -> None:
    return None


def make_started_room(total_rounds: int, round_seconds: int = 0) -> Room:
    room = Room(code="TIMER")
    emma = add_player(room, "Emma")
    jake = add_player(room, "Jake")
    add_photo(room, owner_id=emma.id, url="/uploads/emma.jpg")
    add_photo(room, owner_id=jake.id, url="/uploads/jake.jpg")
    start_game(room, total_rounds=total_rounds, round_seconds=round_seconds)
    return room


@pytest.mark.anyio
async def test_driver_emits_round_and_finish_events_in_order():
    room = make_started_room(total_rounds=2)
    events = []

    driver = RoundDriver(
        room,
        sleep=_noop_sleep,
        on_event=lambda evt: events.append(evt["type"]),
    )
    await driver.run()

    # 2 rounds: start, reveal, start, reveal, then finish.
    assert events == [
        "round_started",
        "round_revealed",
        "round_started",
        "round_revealed",
        "game_finished",
    ]


@pytest.mark.anyio
async def test_driver_finishes_the_room_state():
    room = make_started_room(total_rounds=1)
    driver = RoundDriver(room, sleep=_noop_sleep, on_event=lambda e: None)
    await driver.run()
    assert room.state.value == "finished"


@pytest.mark.anyio
async def test_round_started_event_carries_photo_and_index():
    room = make_started_room(total_rounds=1)
    starts = []
    driver = RoundDriver(
        room,
        sleep=_noop_sleep,
        on_event=lambda e: starts.append(e) if e["type"] == "round_started" else None,
    )
    await driver.run()
    assert starts[0]["round_index"] == 0
    assert "photo" in starts[0]
    assert starts[0]["photo"]["url"]


@pytest.mark.anyio
async def test_round_started_withholds_the_photo_owner():
    # round_started is broadcast to every client before anyone guesses, so
    # shipping the owner there hands out the answer to the live round.
    room = make_started_room(total_rounds=1)
    events = []
    driver = RoundDriver(room, sleep=_noop_sleep, on_event=events.append)
    await driver.run()

    started = next(e for e in events if e["type"] == "round_started")
    assert "owner_id" not in started["photo"]
    assert "owner_id" not in str(started)
    # ...and the reveal still discloses it, since it drives the reveal UI.
    revealed = next(e for e in events if e["type"] == "round_revealed")
    assert revealed["owner_id"] == room.rounds[0].photo.owner_id


@pytest.mark.anyio
async def test_reveal_event_includes_correct_owner():
    room = make_started_room(total_rounds=1)
    reveals = []
    driver = RoundDriver(
        room,
        sleep=_noop_sleep,
        on_event=lambda e: reveals.append(e) if e["type"] == "round_revealed" else None,
    )
    await driver.run()
    assert "owner_id" in reveals[0]


@pytest.mark.anyio
async def test_reveal_event_carries_standings_ranked_by_score():
    """The between-rounds scoreboard reads this: it must arrive ranked."""
    room = make_started_room(total_rounds=1)
    # Give the second player a lead, so "ranked" is distinguishable from
    # "join order" -- otherwise this passes on an unsorted list.
    room.players[1].score = 500
    reveals = []
    driver = RoundDriver(
        room,
        sleep=_noop_sleep,
        on_event=lambda e: reveals.append(e) if e["type"] == "round_revealed" else None,
    )
    await driver.run()

    standings = reveals[0]["standings"]
    assert [p["name"] for p in standings] == ["Jake", "Emma"]
    assert standings[0]["score"] == 500


@pytest.mark.anyio
async def test_round_started_event_carries_server_authoritative_deadline():
    room = make_started_room(total_rounds=1, round_seconds=10)
    starts = []
    driver = RoundDriver(
        room,
        sleep=_noop_sleep,
        time_fn=lambda: 1000.0,
        on_event=lambda e: starts.append(e) if e["type"] == "round_started" else None,
    )
    await driver.run()
    assert starts[0]["round_ends_at"] == int((1000.0 + 10) * 1000)


# --- early end -------------------------------------------------------------

def _guess(room, guesser, guessed_owner_id: str) -> None:
    room.rounds[room.current_round].guesses[guesser.id] = guessed_owner_id


@pytest.mark.anyio
async def test_round_ends_early_once_every_player_has_guessed():
    room = make_started_room(total_rounds=1, round_seconds=30)
    events = []
    steps = []

    async def counting_sleep(seconds: float) -> None:
        steps.append(seconds)

    for player in room.players:
        _guess(room, player, room.players[0].id)

    driver = RoundDriver(
        room,
        sleep=counting_sleep,
        on_event=lambda e: events.append(e["type"]),
    )
    await driver.run()

    assert events == ["round_started", "round_revealed", "game_finished"]
    # One poll to notice everyone guessed, then the reveal hold -- not the
    # full 30s round.
    assert steps == [0.2, REVEAL_SECONDS]


@pytest.mark.anyio
async def test_round_waits_out_the_timeout_when_only_some_have_guessed():
    room = make_started_room(total_rounds=1, round_seconds=30)
    steps = []

    async def counting_sleep(seconds: float) -> None:
        steps.append(seconds)

    _guess(room, room.players[0], room.players[0].id)

    driver = RoundDriver(room, sleep=counting_sleep, on_event=lambda e: None)
    await driver.run()

    # One player short -> no early end, the full 30s is polled out (plus the
    # reveal hold at the end of the round).
    assert sum(steps) == pytest.approx(30 + REVEAL_SECONDS)
    assert room.state.value == "finished"


@pytest.mark.anyio
async def test_reveal_is_held_before_the_next_round_starts():
    # Without the hold, round_revealed and the next round_started land in the
    # same tick and players never see whose photo it was.
    room = make_started_room(total_rounds=2, round_seconds=10)
    timeline = []

    async def recording_sleep(seconds: float) -> None:
        timeline.append(("sleep", seconds))

    driver = RoundDriver(
        room,
        sleep=recording_sleep,
        on_event=lambda e: timeline.append(("event", e["type"])),
    )
    await driver.run()

    # Between each reveal and the following round_started there must be a sleep.
    types = [t for t in timeline if t[0] == "event" or t[1] == REVEAL_SECONDS]
    reveal = types.index(("event", "round_revealed"))
    assert types[reveal + 1] == ("sleep", REVEAL_SECONDS)
    assert types[reveal + 2] == ("event", "round_started")


@pytest.mark.anyio
async def test_round_two_does_not_end_early_from_round_ones_guesses():
    # everyone_has_guessed reads the *current* round; if it ever looked at a
    # stale round, every round after the first would end instantly.
    room = make_started_room(total_rounds=2, round_seconds=30)
    steps = []

    async def counting_sleep(seconds: float) -> None:
        steps.append(seconds)

    for player in room.players:
        _guess(room, player, room.players[0].id)

    driver = RoundDriver(room, sleep=counting_sleep, on_event=lambda e: None)
    await driver.run()

    # Round 0 ends on the first poll; round 1 has no guesses and polls out.
    round_polls = [s for s in steps if s != REVEAL_SECONDS]
    assert sum(round_polls) == pytest.approx(0.2 + 30)


@pytest.mark.anyio
async def test_driver_stops_if_the_room_moved_on_while_it_waited():
    room = make_started_room(total_rounds=2, round_seconds=10)
    events = []

    async def hijacking_sleep(seconds: float) -> None:
        # Simulate the room being reset out from under the driver mid-round.
        room.state = RoomState.LOBBY

    driver = RoundDriver(
        room,
        sleep=hijacking_sleep,
        on_event=lambda e: events.append(e["type"]),
    )
    await driver.run()

    # It must not reveal a round it is no longer timing.
    assert events == ["round_started"]


# --- concurrent mutation of shared Room state ------------------------------
#
# This is asyncio, so only an await can interleave. The driver's injected
# `sleep` IS that await point: mutating the room inside it reproduces exactly
# what a REST handler does when it runs while the driver is sleeping.

def _finish_and_restart(room, total_rounds: int = 2) -> None:
    """What POST /reset + POST /start do to a room between two awaits."""
    room.state = RoomState.FINISHED
    reset_room(room)
    start_game(room, total_rounds=total_rounds, round_seconds=0)


@pytest.mark.anyio
async def test_driver_does_not_advance_a_room_restarted_during_the_reveal_hold():
    # Reset is refused mid-round, but the room can finish and be restarted
    # while the previous driver sleeps out its reveal hold. Advancing then
    # would skip the new game's first round.
    room = make_started_room(total_rounds=3, round_seconds=0)
    events = []
    restarted = False

    async def sleep_then_restart(seconds: float) -> None:
        nonlocal restarted
        if seconds == REVEAL_SECONDS and not restarted:
            restarted = True
            _finish_and_restart(room, total_rounds=3)

    driver = RoundDriver(
        room,
        sleep=sleep_then_restart,
        on_event=lambda e: events.append(e["type"]),
    )
    await driver.run()

    # The stale driver bows out; the fresh game is untouched at round 0.
    assert room.current_round == 0
    assert room.state is RoomState.IN_ROUND
    assert events == ["round_started", "round_revealed"]


@pytest.mark.anyio
async def test_stale_driver_does_not_drive_a_restarted_room():
    # A restart spawns a second driver while the first may still be alive.
    # Only the driver owning the current epoch may advance rounds.
    room = make_started_room(total_rounds=2, round_seconds=0)
    stale = RoundDriver(room, sleep=_noop_sleep, on_event=lambda e: None)

    _finish_and_restart(room, total_rounds=2)

    await stale.run()
    assert room.current_round == 0
    assert room.state is RoomState.IN_ROUND

    fresh_events = []
    fresh = RoundDriver(
        room, sleep=_noop_sleep, on_event=lambda e: fresh_events.append(e["type"])
    )
    await fresh.run()
    assert fresh_events == [
        "round_started",
        "round_revealed",
        "round_started",
        "round_revealed",
        "game_finished",
    ]


@pytest.mark.anyio
async def test_stale_driver_does_not_emit_game_finished_for_a_restarted_room():
    room = make_started_room(total_rounds=1, round_seconds=0)
    events = []
    stale = RoundDriver(room, sleep=_noop_sleep, on_event=lambda e: events.append(e))

    _finish_and_restart(room, total_rounds=1)

    await stale.run()
    # Announcing rankings for a game that just restarted would drop every
    # client straight to the results screen.
    assert events == []


@pytest.mark.anyio
async def test_driver_stops_polling_a_round_it_no_longer_owns():
    # A restart during the wait must end the poll loop immediately, not leave
    # the stale driver ticking out the remaining 10s of a dead round.
    room = make_started_room(total_rounds=2, round_seconds=10)
    steps = []
    restarted = False

    async def sleep_then_restart(seconds: float) -> None:
        nonlocal restarted
        steps.append(seconds)
        if not restarted:
            restarted = True
            _finish_and_restart(room, total_rounds=2)

    driver = RoundDriver(room, sleep=sleep_then_restart, on_event=lambda e: None)
    await driver.run()

    # One poll, then it notices the epoch moved and bails -- not 50 polls.
    assert steps == [0.2]
    # And the freshly restarted game is left exactly where it started.
    assert room.current_round == 0
    assert room.state is RoomState.IN_ROUND
