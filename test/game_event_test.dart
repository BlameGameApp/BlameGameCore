// Unit tests for decoding backend WebSocket events into GameEvent objects.
// Pure Dart logic — runs with `flutter test`, no emulator.

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_blame/models/game_models.dart';

void main() {
  test('decodes player_joined', () {
    final e = GameEvent.fromJson({
      'type': 'player_joined',
      'player': {'id': 'p1', 'name': 'Emma', 'score': 0, 'is_host': true},
    });
    expect(e, isA<PlayerJoined>());
    expect((e as PlayerJoined).player.name, 'Emma');
    expect(e.player.isHost, true);
  });

  test('decodes round_started with photo and server deadline', () {
    final e = GameEvent.fromJson({
      'type': 'round_started',
      'round_index': 2,
      'photo': {'id': 'ph1', 'owner_id': 'p1', 'url': '/rooms/AB/photos/x.jpg'},
      'round_ends_at': 1700000010000,
    });
    expect(e, isA<RoundStarted>());
    final r = e as RoundStarted;
    expect(r.roundIndex, 2);
    expect(r.photo.ownerId, 'p1');
    expect(r.roundEndsAt, 1700000010000);
  });

  test('decodes round_revealed', () {
    final e = GameEvent.fromJson({
      'type': 'round_revealed',
      'round_index': 0,
      'owner_id': 'p9',
    });
    expect((e as RoundRevealed).ownerId, 'p9');
    // A reveal without standings still decodes (older server, or no scores).
    expect(e.standings, isEmpty);
  });

  test('decodes round_revealed standings in the order sent', () {
    final e = GameEvent.fromJson({
      'type': 'round_revealed',
      'round_index': 1,
      'owner_id': 'p9',
      'standings': [
        {'id': 'p9', 'name': 'Jake', 'score': 800},
        {'id': 'p1', 'name': 'Emma', 'score': 300},
      ],
    }) as RoundRevealed;
    expect(e.standings.map((p) => p.name), ['Jake', 'Emma']);
    expect(e.standings.first.score, 800);
  });

  test('decodes guess_result', () {
    final e = GameEvent.fromJson({
      'type': 'guess_result',
      'guesser_id': 'p2',
      'points': 700,
      'correct': true,
    });
    final g = e as GuessResult;
    expect(g.points, 700);
    expect(g.correct, true);
  });

  test('decodes game_finished with ranked players', () {
    final e = GameEvent.fromJson({
      'type': 'game_finished',
      'rankings': [
        {'id': 'p2', 'name': 'Jake', 'score': 800, 'is_host': false},
        {'id': 'p1', 'name': 'Emma', 'score': 0, 'is_host': true},
      ],
    });
    final f = e as GameFinished;
    expect(f.rankings.first.name, 'Jake');
    expect(f.rankings.first.score, 800);
  });

  test('decodes room_reset with reset players', () {
    final e = GameEvent.fromJson({
      'type': 'room_reset',
      'players': [
        {'id': 'p1', 'name': 'Emma', 'score': 0, 'is_host': true},
        {'id': 'p2', 'name': 'Jake', 'score': 0, 'is_host': false},
      ],
    });
    expect(e, isA<RoomReset>());
    final r = e as RoomReset;
    expect(r.players.map((p) => p.name), ['Emma', 'Jake']);
    expect(r.players.every((p) => p.score == 0), true);
  });

  test('decodes player_left with the refreshed roster', () {
    final e = GameEvent.fromJson({
      'type': 'player_left',
      'player_id': 'p2',
      'kicked': true,
      'players': [
        {'id': 'p1', 'name': 'Emma', 'score': 0, 'is_host': true},
      ],
    });
    expect(e, isA<PlayerLeft>());
    final left = e as PlayerLeft;
    expect(left.playerId, 'p2');
    expect(left.kicked, isTrue);
    expect(left.players.map((p) => p.name), ['Emma']);
  });

  test('player_left defaults kicked to false when absent', () {
    final e = GameEvent.fromJson({
      'type': 'player_left',
      'player_id': 'p2',
      'players': <Map<String, dynamic>>[],
    });
    expect((e as PlayerLeft).kicked, isFalse);
  });

  test('unknown event type falls back to UnknownEvent', () {
    final e = GameEvent.fromJson({'type': 'something_new'});
    expect(e, isA<UnknownEvent>());
  });
}
