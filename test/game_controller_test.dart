import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_blame/models/game_models.dart';
import 'package:photo_blame/services/api_client.dart';
import 'package:photo_blame/services/game_socket.dart';
import 'package:photo_blame/state/game_controller.dart';

import 'support/fakes.dart';

const _snapshot = {
  'state': 'lobby',
  'round_seconds': 10,
  'players': [
    {'id': 'me', 'name': 'Emma', 'is_host': true, 'score': 0},
    {'id': 'p2', 'name': 'Jake', 'is_host': false, 'score': 0},
  ],
};

const _joinOk = {'player_id': 'me', 'is_host': true};
const _guessOk = {'points': 800, 'correct': true};

/// A controller that has completed a join, plus the fakes behind it.
Future<(GameController, FakeGameSocket, RecordingClient)> joinedController({
  Object? guess = _guessOk,
}) async {
  final recording = RecordingClient(
    join: _joinOk,
    snapshot: _snapshot,
    guess: guess,
  );
  final socket = FakeGameSocket();
  final controller = GameController(
    api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
    socketFactory: fakeSocketFactory(socket),
  );
  await controller.joinByCode('ABC12', 'Emma');
  return (controller, socket, recording);
}

/// A joined controller on millisecond timings, so heartbeat and retry tests
/// run at test speed instead of waiting real seconds.
Future<GameController> _heartbeatController(
  ReconnectingSocketFactory sockets, {
  List<Duration> backoff = const [Duration(milliseconds: 5)],
  Duration heartbeat = const Duration(milliseconds: 20),
}) async {
  final recording = RecordingClient(join: _joinOk, snapshot: _snapshot);
  final controller = GameController(
    api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
    socketFactory: sockets.factory,
    heartbeatInterval: heartbeat,
    retryBackoff: backoff,
  );
  await controller.joinByCode('ABC12', 'Emma');
  return controller;
}

/// Sockets after the first never finish closing, like a real one that is
/// closed while it's still connecting.
class _HangingCloseSocket extends FakeGameSocket {
  @override
  Future<void> close() {
    closed = true;
    return Completer<void>().future;
  }
}

class _HangingCloseFactory {
  final sockets = <FakeGameSocket>[];
  FakeGameSocket get latest => sockets.last;

  GameSocket factory(String code, String playerId) {
    final socket = sockets.isEmpty ? FakeGameSocket() : _HangingCloseSocket();
    sockets.add(socket);
    return socket;
  }
}

void main() {
  group('joining', () {
    test('wires identity, roster, and socket', () async {
      final (c, socket, _) = await joinedController();

      expect(c.roomCode, 'ABC12');
      expect(c.myPlayerId, 'me');
      expect(c.isHost, isTrue);
      expect(c.roundSeconds, 10);
      expect(c.players.map((p) => p.name), ['Emma', 'Jake']);
      // The socket must be opened for the room we actually joined.
      expect(socket.code, 'ABC12');
      expect(socket.playerId, 'me');
    });

    test('the photo mode is learned from the room snapshot', () async {
      final (normal, _, _) = await joinedController();
      expect(normal.hardcore, isFalse);
      expect(normal.photoModeKnown, isTrue);

      final recording = RecordingClient(
        join: _joinOk,
        snapshot: {..._snapshot, 'hardcore': true},
      );
      final hard = GameController(
        api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(FakeGameSocket()),
      );
      await hard.joinByCode('ABC12', 'Emma');
      expect(hard.hardcore, isTrue);
    });

    test('the mode stays unknown until a snapshot lands', () async {
      final controller = GameController(
        api: ApiClient(
          httpClient: RecordingClient(join: _joinOk, snapshot: 500).client,
          baseUrl: 'http://test',
        ),
        socketFactory: fakeSocketFactory(FakeGameSocket()),
      );
      expect(controller.photoModeKnown, isFalse);

      // A failed join must not leave a mode behind that would let a client
      // sample: unknown is not the same as normal.
      await expectLater(
        controller.joinByCode('ABC12', 'Emma'),
        throwsA(isA<ApiException>()),
      );
      expect(controller.hardcore, isNull);
      expect(controller.photoModeKnown, isFalse);
    });

    test('a failed snapshot leaves no half-joined controller', () async {
      final recording = RecordingClient(join: _joinOk, snapshot: 500);
      final controller = GameController(
        api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(FakeGameSocket()),
      );

      await expectLater(
        controller.joinByCode('ABC12', 'Emma'),
        throwsA(isA<ApiException>()),
      );
      expect(controller.roomCode, isNull);
      expect(controller.myPlayerId, isNull);
    });

    test('a player who joins during the snapshot is not lost', () async {
      // The socket is opened before the snapshot is fetched, so an event that
      // races the snapshot must survive the merge rather than be overwritten.
      final socket = FakeGameSocket();
      // Fire the event while the snapshot request is in flight -- i.e. after
      // the socket is connected but before the roster comes back.
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/join')) {
          return http.Response(jsonEncode(_joinOk), 200);
        }
        socket.emit(PlayerJoined(player(id: 'late', name: 'Sam')));
        await pumpEventQueue();
        return http.Response(jsonEncode(_snapshot), 200);
      });
      final controller = GameController(
        api: ApiClient(httpClient: client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(socket),
      );

      await controller.joinByCode('ABC12', 'Emma');

      expect(
        controller.players.map((p) => p.name),
        containsAll(['Emma', 'Jake', 'Sam']),
      );
    });

    test('the exposed player list cannot be mutated by callers', () async {
      final (c, _, _) = await joinedController();
      expect(() => c.players.add(player(id: 'x')), throwsUnsupportedError);
    });
  });

  group('events', () {
    test('player_joined appends, and ignores a duplicate id', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(PlayerJoined(player(id: 'p3', name: 'Sam')));
      await pumpEventQueue();
      expect(c.players.length, 3);

      socket.emit(PlayerJoined(player(id: 'p3', name: 'Sam')));
      await pumpEventQueue();
      expect(c.players.length, 3, reason: 'a replayed join must not duplicate');
    });

    test('round_started resets every per-round field', () async {
      final (c, socket, _) = await joinedController();

      // Drive round 0 into a guessed + revealed state.
      socket.emit(const RoundStarted(
        roundIndex: 0,
        photo: PhotoInfo(id: 'ph0', ownerId: 'p2', url: '/a.jpg'),
        roundEndsAt: 1000,
      ));
      await pumpEventQueue();
      await c.guess('p2');
      socket.emit(const GuessResult(guesserId: 'me', points: 700, correct: true));
      socket.emit(const RoundRevealed(roundIndex: 0, ownerId: 'p2'));
      await pumpEventQueue();
      expect(c.phase, GamePhase.revealed);

      socket.emit(const RoundStarted(
        roundIndex: 1,
        photo: PhotoInfo(id: 'ph1', ownerId: 'me', url: '/b.jpg'),
        roundEndsAt: 2000,
      ));
      await pumpEventQueue();

      expect(c.roundIndex, 1);
      expect(c.currentPhoto?.id, 'ph1');
      expect(c.roundEndsAt, 2000);
      expect(c.revealedOwnerId, isNull);
      expect(c.hasGuessedThisRound, isFalse);
      expect(c.lastPointsEarned, isNull);
      expect(c.phase, GamePhase.inRound);
    });

    test('guess_result accumulates the live score', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(const GuessResult(guesserId: 'me', points: 800, correct: true));
      await pumpEventQueue();
      expect(c.me?.score, 800, reason: 'the in-game score badge reads this');
      expect(c.lastPointsEarned, 800);

      socket.emit(const GuessResult(guesserId: 'me', points: 300, correct: true));
      await pumpEventQueue();
      expect(c.me?.score, 1100, reason: 'scores accumulate across rounds');
    });

    test('another player\'s guess_result updates them, not me', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(const GuessResult(guesserId: 'p2', points: 500, correct: true));
      await pumpEventQueue();

      expect(c.players.firstWhere((p) => p.id == 'p2').score, 500);
      expect(c.me?.score, 0);
      expect(c.lastPointsEarned, isNull, reason: 'only my own result banners');
    });

    test('photos_updated refreshes readiness and unblocks starting', () async {
      final (c, socket, _) = await joinedController();
      expect(c.canStart, isFalse, reason: 'nobody has uploaded yet');

      socket.emit(PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 3),
        player(id: 'p2', name: 'Jake', photoCount: 2),
      ]));
      await pumpEventQueue();

      expect(c.players.every((p) => p.hasPhotos), isTrue);
      expect(c.canStart, isTrue);
    });

    test('one uploader is not enough to start', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(PhotosUpdated([
        player(id: 'me', name: 'Emma', isHost: true, photoCount: 5),
        player(id: 'p2', name: 'Jake'),
      ]));
      await pumpEventQueue();

      expect(c.canStart, isFalse);
    });

    test('game_finished stores rankings and finishes', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(GameFinished([
        player(id: 'p2', name: 'Jake', score: 900),
        player(id: 'me', name: 'Emma', score: 400),
      ]));
      await pumpEventQueue();

      expect(c.phase, GamePhase.finished);
      expect(c.finalRankings.first.name, 'Jake');
      expect(() => c.finalRankings.add(player()), throwsUnsupportedError);
    });

    test('room_reset restores a clean lobby for the next game', () async {
      final (c, socket, _) = await joinedController();
      socket.emit(const RoundStarted(
        roundIndex: 2,
        photo: PhotoInfo(id: 'ph', ownerId: 'p2', url: '/a.jpg'),
        roundEndsAt: 1000,
      ));
      socket.emit(GameFinished([player(id: 'me', score: 900)]));
      await pumpEventQueue();

      socket.emit(RoomReset([
        player(id: 'me', name: 'Emma', isHost: true, score: 900),
        player(id: 'p2', name: 'Jake', score: 400),
      ]));
      await pumpEventQueue();

      expect(c.phase, GamePhase.lobby);
      expect(c.roundIndex, 0);
      expect(c.currentPhoto, isNull);
      expect(c.roundEndsAt, isNull);
      expect(c.revealedOwnerId, isNull);
      expect(c.hasGuessedThisRound, isFalse);
      expect(c.lastPointsEarned, isNull);
      expect(c.finalRankings, isEmpty);
      // Scores carry over between games.
      expect(c.me?.score, 900);
    });

    test('an unknown event type is ignored, not fatal', () async {
      final (c, socket, _) = await joinedController();
      socket.emit(const UnknownEvent('something_new'));
      await pumpEventQueue();
      expect(c.phase, GamePhase.lobby);
    });
  });

  group('connection loss', () {
    test('a dropped socket surfaces instead of freezing silently', () async {
      final (c, socket, _) = await joinedController();
      expect(c.connectionError, isNull);

      socket.dropConnection();
      await pumpEventQueue();

      expect(c.connectionError, isNotNull);
    });

    test('a stream error surfaces too', () async {
      final (c, socket, _) = await joinedController();
      socket.emitError(Exception('boom'));
      await pumpEventQueue();
      expect(c.connectionError, isNotNull);
    });

    test('reconnect re-seeds from the server and clears the error', () async {
      // Fresh socket per connect: a reused fake stays closed after the drop,
      // so the "reconnected" socket would report dead the instant we listen.
      final recording = RecordingClient(join: _joinOk, snapshot: _snapshot);
      final sockets = ReconnectingSocketFactory();
      final c = GameController(
        api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
        socketFactory: sockets.factory,
        heartbeatInterval: Duration.zero,
        retryBackoff: const [],
      );
      await c.joinByCode('ABC12', 'Emma');
      sockets.latest.dropConnection();
      await pumpEventQueue();
      expect(c.connectionError, isNotNull);

      await c.reconnect();

      expect(c.connectionError, isNull);
      // Events missed while offline are gone, so state must come from the
      // snapshot, not be assumed.
      expect(recording.countEndingWith('/ABC12'), 2);
      expect(c.players.length, 2);
    });

    test('normal disposal does not raise a connection error', () async {
      final (c, _, _) = await joinedController();
      c.dispose();
      await pumpEventQueue();
      expect(c.connectionError, isNull);
    });
  });

  group('heartbeat', () {
    test('pings on the interval while frames keep arriving', () async {
      final sockets = ReconnectingSocketFactory();
      final c = await _heartbeatController(sockets);
      addTearDown(c.dispose);

      // Answer each beat, as a live server would.
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 12));
        sockets.latest.emit(const UnknownEvent('pong'));
        await pumpEventQueue();
      }

      expect(sockets.latest.pings, greaterThan(0));
      expect(c.connectionError, isNull);
    });

    test('a silent interval is treated as a dead socket', () async {
      final sockets = ReconnectingSocketFactory();
      // No auto-retry here, so the failure is the heartbeat's alone.
      final c = await _heartbeatController(sockets, backoff: const []);
      addTearDown(c.dispose);

      // Two ticks with nothing coming back: the first pings, the second finds
      // no reply and declares the socket dead. The fake never answers.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(c.connectionError, isNotNull);
    });
  });

  group('auto-reconnect', () {
    test('a drop reconnects on its own, without the player tapping RETRY',
        () async {
      final sockets = ReconnectingSocketFactory();
      // Heartbeat off: this is about the drop, and a fake socket never answers
      // a ping, so a live heartbeat would kill the reconnected socket too.
      final c = await _heartbeatController(sockets, heartbeat: Duration.zero);
      addTearDown(c.dispose);

      sockets.latest.dropConnection();
      await pumpEventQueue();
      expect(c.connectionError, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(c.connectionError, isNull);
      // A fresh socket, not the closed one.
      expect(sockets.sockets.length, 2);
      expect(sockets.latest.closed, isFalse);
    });

    test('retries are bounded and the banner comes back when they run out',
        () async {
      final sockets = ReconnectingSocketFactory();
      // The room goes unreachable after the join, so no retry can ever
      // recover -- the only way to reach the end of the backoff list.
      var roomIsUp = true;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/join')) {
          return http.Response(jsonEncode(_joinOk), 200);
        }
        if (!roomIsUp) return http.Response('{"detail":"down"}', 503);
        return http.Response(jsonEncode(_snapshot), 200);
      });
      final c = GameController(
        api: ApiClient(httpClient: client, baseUrl: 'http://test'),
        socketFactory: sockets.factory,
        heartbeatInterval: Duration.zero,
        retryBackoff: const [
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
        ],
      );
      await c.joinByCode('ABC12', 'Emma');
      addTearDown(c.dispose);
      roomIsUp = false;

      sockets.latest.dropConnection();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // 1 initial + 2 retries, and then it stops rather than hammering on.
      expect(sockets.sockets.length, 3);
      expect(c.connectionError, isNotNull);
      expect(c.isReconnecting, isFalse);
    });

    // A real socket that is still connecting never finishes closing, and an
    // outage is exactly when one gets closed: the HTTP call fails at once while
    // the socket is still trying. Waiting on it froze the whole retry chain with
    // the error already cleared, so the game went quiet with no banner up.
    test('an outage is reported even when a half-open socket never closes',
        () async {
      final sockets = _HangingCloseFactory();
      var serverIsUp = true;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/join')) {
          return http.Response(jsonEncode(_joinOk), 200);
        }
        if (!serverIsUp) throw http.ClientException('connection refused');
        return http.Response(jsonEncode(_snapshot), 200);
      });
      final c = GameController(
        api: ApiClient(httpClient: client, baseUrl: 'http://test'),
        socketFactory: sockets.factory,
        heartbeatInterval: Duration.zero,
        retryBackoff: const [
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
        ],
      );
      await c.joinByCode('ABC12', 'Emma');
      addTearDown(c.dispose);
      serverIsUp = false;

      sockets.latest.dropConnection();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(c.connectionError, isNotNull);
      // 1 initial + 2 retries: the chain ran to the end instead of stalling.
      expect(sockets.sockets.length, 3);
    });

    test('a room the server no longer has ends the game, without more retries',
        () async {
      final sockets = ReconnectingSocketFactory();
      var roomExists = true;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/join')) {
          return http.Response(jsonEncode(_joinOk), 200);
        }
        if (!roomExists) {
          return http.Response('{"detail":"room not found"}', 404);
        }
        return http.Response(jsonEncode(_snapshot), 200);
      });
      final c = GameController(
        api: ApiClient(httpClient: client, baseUrl: 'http://test'),
        socketFactory: sockets.factory,
        heartbeatInterval: Duration.zero,
        retryBackoff: const [
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
          Duration(milliseconds: 5),
        ],
      );
      await c.joinByCode('ABC12', 'Emma');
      addTearDown(c.dispose);
      roomExists = false;

      sockets.latest.dropConnection();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(c.hasLeftRoom, isTrue);
      expect(c.removedFromRoom, isNotNull);
      expect(c.connectionError, isNull);
      // 1 initial + the 1 retry that found out, and no point in any more.
      expect(sockets.sockets.length, 2);
      expect(c.isReconnecting, isFalse);
    });

    test('disposal cancels the pending retry', () async {
      final sockets = ReconnectingSocketFactory();
      final c = await _heartbeatController(
        sockets,
        backoff: const [Duration(milliseconds: 30)],
      );

      sockets.latest.dropConnection();
      await pumpEventQueue();
      expect(c.isReconnecting, isTrue);

      c.dispose();
      // Long enough for the retry to have fired. A live timer would reconnect
      // on a disposed controller and throw.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(sockets.sockets.length, 1);
    });
  });

  group('guessing', () {
    test('locks the round and sends the round index', () async {
      final (c, socket, recording) = await joinedController();
      socket.emit(const RoundStarted(
        roundIndex: 4,
        photo: PhotoInfo(id: 'ph', ownerId: 'p2', url: '/a.jpg'),
        roundEndsAt: 1000,
      ));
      await pumpEventQueue();

      await c.guess('p2');

      expect(c.hasGuessedThisRound, isTrue);
      final body = (recording.requests.last as dynamic).body as String;
      expect(body, contains('"round_index":4'));
      expect(body, isNot(contains('seconds_left')));
    });

    test('a second guess in the same round makes no request', () async {
      final (c, _, recording) = await joinedController();

      await c.guess('p2');
      await c.guess('p2');

      expect(recording.countEndingWith('/guess'), 1);
    });

    test('a failed guess releases the lock so the player can retry', () async {
      final (c, _, _) = await joinedController(guess: 500);

      await expectLater(c.guess('p2'), throwsA(isA<ApiException>()));

      expect(
        c.hasGuessedThisRound,
        isFalse,
        reason: 'a transient failure must not lock the player out of the round',
      );
    });
  });

  group('uploading', () {
    test('one failed photo does not cost the rest of the batch', () async {
      var uploadAttempts = 0;
      final socket = FakeGameSocket();
      final client = MockClient((request) async {
        if (request.url.path.contains('/photos')) {
          uploadAttempts++;
          // The second photo fails; the others must still land.
          if (uploadAttempts == 2) {
            return http.Response('{"detail":"too large"}', 413);
          }
          return http.Response(jsonEncode({'url': '/p.jpg'}), 200);
        }
        if (request.url.path.endsWith('/join')) {
          return http.Response(jsonEncode(_joinOk), 200);
        }
        return http.Response(jsonEncode(_snapshot), 200);
      });
      final c = GameController(
        api: ApiClient(httpClient: client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(socket),
      );
      await c.joinByCode('ABC12', 'Emma');

      final uploaded = await c.uploadPhotos([
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
        Uint8List.fromList([3]),
      ]);

      expect(uploadAttempts, 3, reason: 'the batch continues past a failure');
      expect(uploaded, 2, reason: 'and reports how many actually landed');
    });
  });

  group('leaving and kicking', () {
    test('leaveRoom posts and closes the socket', () async {
      final (c, socket, recording) = await joinedController();

      await c.leaveRoom();

      expect(recording.countEndingWith('/leave'), 1);
      expect(c.hasLeftRoom, isTrue);
      // Staying on the feed for a room we've left would surface as a bogus
      // "lost connection" banner on the way out.
      expect(socket.closed, isTrue);
    });

    test('kickPlayer posts the host id and the target', () async {
      final (c, _, recording) = await joinedController();

      await c.kickPlayer('p2');

      final request = recording.requests.last as http.Request;
      expect(request.url.path, endsWith('/kick'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['host_id'], 'me');
      expect(body['player_id'], 'p2');
    });

    test('player_left for someone else just refreshes the roster', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(PlayerLeft(
        playerId: 'p2',
        kicked: false,
        players: [player(id: 'me', name: 'Emma', isHost: true)],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(c.players.map((p) => p.id), ['me']);
      expect(c.hasLeftRoom, isFalse);
    });

    test('player_left for me marks us out and names the reason', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(PlayerLeft(
        playerId: 'me',
        kicked: true,
        players: [player(id: 'p2', name: 'Jake', isHost: true)],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(c.hasLeftRoom, isTrue);
      expect(c.removedFromRoom, isNotNull);
    });

    test('leaving of my own accord carries no kicked reason', () async {
      final (c, socket, _) = await joinedController();

      socket.emit(PlayerLeft(
        playerId: 'me',
        kicked: false,
        players: const [],
      ));
      await Future<void>.delayed(Duration.zero);

      expect(c.hasLeftRoom, isTrue);
      expect(c.removedFromRoom, isNull);
    });

    test('inheriting the host role is picked up from the roster', () async {
      // Join as a non-host, then watch the host leave.
      final recording = RecordingClient(
        join: {'player_id': 'me', 'is_host': false},
        snapshot: _snapshot,
      );
      final socket = FakeGameSocket();
      final c = GameController(
        api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(socket),
      );
      await c.joinByCode('ABC12', 'Emma');
      expect(c.isHost, isFalse);

      socket.emit(PlayerLeft(
        playerId: 'p2',
        kicked: false,
        players: [player(id: 'me', name: 'Emma', isHost: true)],
      ));
      await Future<void>.delayed(Duration.zero);

      // Trusting the join-time value would leave the room with no one able to
      // start it.
      expect(c.isHost, isTrue);
    });
  });

  group('mid-game state reconstruction', () {
    /// A controller joined into a room whose snapshot reports [state].
    Future<(GameController, RecordingClient)> joinedInto(
      String state, {
      Map<String, dynamic>? round,
    }) async {
      final recording = RecordingClient(
        join: _joinOk,
        snapshot: {
          ..._snapshot,
          'state': state,
          'round': ?round,
        },
      );
      final c = GameController(
        api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(FakeGameSocket()),
      );
      await c.joinByCode('ABC12', 'Emma');
      return (c, recording);
    }

    test('a lobby snapshot leaves the controller in the lobby', () async {
      final (c, _) = await joinedInto('lobby');
      expect(c.phase, GamePhase.lobby);
      expect(c.currentPhoto, isNull);
    });

    test('joining mid-round lands in the round, not the lobby', () async {
      final (c, recording) = await joinedInto('in_round', round: {
        'index': 3,
        'photo': {'id': 'ph9', 'url': '/9.jpg'},
        'ends_at': 1700000000500,
        'has_guessed': false,
      });

      expect(c.phase, GamePhase.inRound);
      expect(c.roundIndex, 3);
      expect(c.currentPhoto?.url, '/9.jpg');
      expect(c.roundEndsAt, 1700000000500);
      expect(c.hasGuessedThisRound, isFalse);
      // Without the owner there is no answer to leak, so the reveal banner
      // stays empty until round_revealed says otherwise.
      expect(c.revealedOwnerId, isNull);
      // The snapshot must be scoped to us, or has_guessed is meaningless.
      expect(
        recording.requests.last.url.queryParameters['player_id'],
        'me',
      );
    });

    test('a guess already spent is not offered again', () async {
      final (c, recording) = await joinedInto('in_round', round: {
        'index': 0,
        'photo': {'id': 'ph', 'url': '/a.jpg'},
        'ends_at': 1,
        'has_guessed': true,
      });

      expect(c.hasGuessedThisRound, isTrue);
      // And the guard holds: a second attempt never reaches the server, which
      // would reject it anyway.
      await c.guess('p2');
      expect(recording.countEndingWith('/guess'), 0);
    });

    test('joining during the reveal shows the answer', () async {
      final (c, _) = await joinedInto('revealing', round: {
        'index': 1,
        'photo': {'id': 'ph', 'owner_id': 'p2', 'url': '/a.jpg'},
        'ends_at': null,
        'has_guessed': true,
      });

      expect(c.phase, GamePhase.revealed);
      expect(c.revealedOwnerId, 'p2');
      expect(c.revealedOwnerName, 'Jake');
      expect(c.roundEndsAt, isNull);
    });

    test('joining after the game ends lands on the results', () async {
      final (c, _) = await joinedInto('finished', round: {
        'index': 4,
        'photo': {'id': 'ph', 'owner_id': 'p2', 'url': '/a.jpg'},
        'ends_at': null,
        'has_guessed': true,
      });

      expect(c.phase, GamePhase.finished);
      // Rankings come off the roster the snapshot already carries — there is
      // no game_finished event left to wait for.
      expect(c.finalRankings.map((p) => p.id), ['me', 'p2']);
    });

    test('reconnecting mid-round restores the round, not the lobby', () async {
      final recording = RecordingClient(
        join: _joinOk,
        snapshot: {
          ..._snapshot,
          'state': 'in_round',
          'round': {
            'index': 2,
            'photo': {'id': 'ph', 'url': '/a.jpg'},
            'ends_at': 1700000000500,
            'has_guessed': true,
          },
        },
      );
      final socket = FakeGameSocket();
      final c = GameController(
        api: ApiClient(httpClient: recording.client, baseUrl: 'http://test'),
        socketFactory: fakeSocketFactory(socket),
      );
      await c.joinByCode('ABC12', 'Emma');
      socket.dropConnection();
      await pumpEventQueue();

      await c.reconnect();

      expect(c.connectionError, isNull);
      expect(c.phase, GamePhase.inRound);
      expect(c.roundIndex, 2);
      expect(c.roundEndsAt, 1700000000500);
      expect(c.hasGuessedThisRound, isTrue);
    });
  });
}
