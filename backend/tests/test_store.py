"""Unit tests for the in-memory GameStore (app/store.py)."""

import pytest

from app.store import GameStore, RoomNotFound, StoreFull


def test_create_room_returns_five_char_code():
    store = GameStore()
    room = store.create_room()
    assert len(room.code) == 5
    assert room.code.isalnum()
    assert room.code.isupper()


def test_created_room_is_retrievable():
    store = GameStore()
    room = store.create_room()
    assert store.get_room(room.code) is room


def test_get_unknown_room_raises():
    store = GameStore()
    with pytest.raises(RoomNotFound):
        store.get_room("ZZZZZ")


def test_room_codes_do_not_collide():
    store = GameStore()
    codes = {store.create_room().code for _ in range(200)}
    assert len(codes) == 200


def test_room_codes_cannot_spell_words():
    # A word needs a vowel, and 3 and 4 stand in for E and A. The code is the
    # largest thing in the lobby and gets read aloud to a room.
    store = GameStore(max_rooms=2000)
    drawn = "".join(store.create_room().code for _ in range(2000))
    assert set(drawn).isdisjoint("AEIOUY034")


class FakeClock:
    """Injectable clock, so eviction tests don't have to wait out a TTL."""

    def __init__(self, now=1000.0):
        self.now = now

    def __call__(self):
        return self.now


def test_idle_room_is_evicted_after_ttl():
    clock = FakeClock()
    store = GameStore(ttl_seconds=60, time_fn=clock)
    room = store.create_room()

    clock.now += 61
    with pytest.raises(RoomNotFound):
        store.get_room(room.code)


def test_room_is_kept_while_it_is_being_used():
    clock = FakeClock()
    store = GameStore(ttl_seconds=60, time_fn=clock)
    room = store.create_room()

    # Touched every 30s: never idle for a full TTL, so it must survive.
    for _ in range(10):
        clock.now += 30
        assert store.get_room(room.code) is room


def test_eviction_calls_on_evict_with_the_room_code():
    clock = FakeClock()
    evicted = []
    store = GameStore(ttl_seconds=60, time_fn=clock, on_evict=evicted.append)
    room = store.create_room()

    clock.now += 61
    assert store.sweep() == [room.code]
    assert evicted == [room.code]


def test_sweep_leaves_fresh_rooms_alone():
    clock = FakeClock()
    evicted = []
    store = GameStore(ttl_seconds=60, time_fn=clock, on_evict=evicted.append)
    stale = store.create_room()
    fresh = store.create_room()

    clock.now += 61
    # Keep only `fresh` alive; create_room sweeps too, so check what it dropped.
    fresh.last_active = clock.now
    assert store.sweep() == [stale.code]
    assert evicted == [stale.code]
    assert store.get_room(fresh.code) is fresh


def test_delete_room_removes_it_and_fires_on_evict():
    evicted = []
    store = GameStore(on_evict=evicted.append)
    room = store.create_room()

    store.delete_room(room.code)
    assert evicted == [room.code]
    with pytest.raises(RoomNotFound):
        store.get_room(room.code)


def test_delete_unknown_room_raises():
    store = GameStore()
    with pytest.raises(RoomNotFound):
        store.delete_room("ZZZZZ")


# --- capacity --------------------------------------------------------------

def test_the_store_refuses_to_grow_past_its_cap():
    # POST /rooms is unauthenticated and every room lives in this process's
    # RAM, so without a ceiling a create loop kills the container and takes
    # every live game with it.
    store = GameStore(max_rooms=3)
    for _ in range(3):
        store.create_room()

    with pytest.raises(StoreFull):
        store.create_room()


def test_expired_rooms_make_room_for_new_ones():
    # The cap must reject a real flood, not a store full of rooms that aged
    # out hours ago.
    now = [1000.0]
    store = GameStore(ttl_seconds=60, max_rooms=2, time_fn=lambda: now[0])
    store.create_room()
    store.create_room()

    now[0] += 61
    fresh = store.create_room()

    assert store.room_count == 1
    assert store.get_room(fresh.code) is fresh


def test_deleting_a_room_frees_capacity():
    store = GameStore(max_rooms=1)
    first = store.create_room()
    with pytest.raises(StoreFull):
        store.create_room()

    store.delete_room(first.code)
    assert store.create_room() is not None
