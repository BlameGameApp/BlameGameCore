import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import '../services/api_client.dart';
import '../services/game_socket.dart';

/// Which phase of the game the UI is in.
enum GamePhase { lobby, inRound, revealed, finished }

/// Identity established once the player has joined a room.
///
/// Modelled as a single object so the "joined" invariant is expressed once:
/// either we have a room and a player id, or we have neither. That removes the
/// `roomCode!` / `myPlayerId!` force-unwraps this class used to carry, and
/// makes a half-joined controller unrepresentable.
@immutable
class GameSession {
  final String roomCode;
  final String playerId;
  final bool isHost;

  const GameSession({
    required this.roomCode,
    required this.playerId,
    required this.isHost,
  });
}

/// Holds all live game state and owns the API + WebSocket connections.
///
/// Screens listen to this ([ChangeNotifier]) and rebuild when it changes.
/// One controller instance is created when a player creates/joins a room and
/// passed down through the screens, which own disposing it.
class GameController extends ChangeNotifier {
  final ApiClient api;
  final GameSocketFactory _socketFactory;

  /// How often to ping, and how long to wait for any frame back before calling
  /// the socket dead. Injectable so tests don't wait real seconds;
  /// [Duration.zero] turns the heartbeat off, which is what widget tests want —
  /// the test framework fails any test that ends with a timer pending.
  final Duration heartbeatInterval;

  /// Backoff before each automatic retry. Bounded on purpose: once these are
  /// spent the banner comes back and RETRY is the player's fallback. An
  /// endless silent retry loop is worse than a visible failure.
  final List<Duration> retryBackoff;

  GameController({
    ApiClient? api,
    GameSocketFactory? socketFactory,
    this.heartbeatInterval = const Duration(seconds: 15),
    this.retryBackoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
  })  : api = api ?? ApiClient(),
        _socketFactory = socketFactory ?? GameSocket.connect;

  GameSession? _session;

  /// Identity of the joined room. Throws if read before a successful join —
  /// screens are only reachable after one, so this never fires in practice.
  GameSession get session =>
      _session ?? (throw StateError('GameController used before joining'));

  String? get roomCode => _session?.roomCode;
  String? get myPlayerId => _session?.playerId;
  bool get isHost => _session?.isHost ?? false;

  // Live state. The backing list stays private so screens can't mutate it
  // behind the notifier's back; `players` is a cached unmodifiable view.
  final List<GamePlayer> _players = [];
  late final List<GamePlayer> players = UnmodifiableListView(_players);

  GamePhase phase = GamePhase.lobby;

  // Round state
  int roundIndex = 0;
  PhotoInfo? currentPhoto;
  String? revealedOwnerId;
  bool hasGuessedThisRound = false;
  int? lastPointsEarned;
  int roundSeconds = 10;
  int totalRounds = 5;

  /// Whether this room uploads photos blind, learned from the room snapshot.
  ///
  /// Null until the snapshot has landed: "mode unknown" is deliberately not
  /// the same as "normal mode". A client that sampled before knowing could
  /// upload blind in a room the player believed showed a preview, so screens
  /// must gate sampling on [photoModeKnown] rather than on `hardcore == true`.
  bool? hardcore;

  /// True once the room's photo mode is known and it is safe to sample.
  bool get photoModeKnown => hardcore != null;

  /// Server epoch-ms deadline for the current round, or null between rounds.
  int? roundEndsAt;

  /// Standings sent with the last reveal, in the server's order. Shown on the
  /// between-rounds scoreboard; empty until the first reveal.
  List<GamePlayer> _standings = const [];
  List<GamePlayer> get standings => UnmodifiableListView(_standings);

  // Results
  List<GamePlayer> _finalRankings = const [];
  List<GamePlayer> get finalRankings => UnmodifiableListView(_finalRankings);

  /// Non-null once the live connection has dropped. Screens surface this and
  /// offer [reconnect]; without it a dropped socket silently freezes the game.
  String? connectionError;

  /// Set once this player is no longer in the room, so screens can pop back
  /// home. Carries a reason when they were kicked; null when they left of
  /// their own accord. Check [hasLeftRoom] rather than this for "am I out?".
  String? removedFromRoom;

  /// True once this player is out of the room, kicked or by choice.
  bool hasLeftRoom = false;

  GameSocket? _socket;
  StreamSubscription<GameEvent>? _sub;

  /// Pings on [heartbeatInterval]; the tick that finds no frame since the last
  /// one declares the socket dead.
  Timer? _heartbeat;

  /// Pending automatic retry, if any. Held so [dispose] can cancel it — a
  /// reconnect firing on a torn-down controller is the TASK-46 crash again.
  Timer? _retryTimer;

  /// Whether any frame (event or pong) arrived since the last heartbeat tick.
  bool _sawFrame = false;

  /// How many automatic retries have been spent on the current outage.
  int _retriesUsed = 0;

  /// True while an automatic retry is pending, so the UI can say "reconnecting"
  /// rather than offering a RETRY that is already happening.
  bool get isReconnecting => _retryTimer != null;

  GamePlayer? get me => _playerById(myPlayerId);

  /// The game needs photos from two different people, or every round shows
  /// the same player's pictures. Mirrors the server's start rule.
  bool get canStart =>
      isHost && _players.length >= 2 && _players.where((p) => p.hasPhotos).length >= 2;

  /// Name of the player whose photo was just revealed, for the result banner.
  String get revealedOwnerName => _playerById(revealedOwnerId)?.name ?? 'someone';

  GamePlayer? _playerById(String? id) {
    if (id == null) return null;
    for (final p in _players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Create a room and join it as the host. Settings are chosen in the lobby.
  Future<void> createAndHost(String name) async {
    final code = await api.createRoom();
    await _join(code, name);
  }

  /// Join an existing room by code.
  Future<void> joinByCode(String code, String name) => _join(code, name);

  Future<void> _join(String code, String name) async {
    final result = await api.joinRoom(code, name);
    _session = GameSession(
      roomCode: code,
      playerId: result.playerId,
      isHost: result.isHost,
    );

    // Connect *before* snapshotting. The other order drops anyone who joins
    // in between: they're missing from the snapshot, and their player_joined
    // went out before this socket existed. Nothing re-syncs the roster
    // mid-game, so that player stays invisible — and every round showing
    // their photo is an automatic zero.
    _connectSocket();
    try {
      _applySnapshot(await api.getRoom(code, playerId: result.playerId));
    } catch (_) {
      // Don't leave a half-joined controller behind.
      await _teardownSocket();
      _session = null;
      _players.clear();
      hardcore = null;
      rethrow;
    }
    notifyListeners();
  }

  /// Seeds every bit of game state the server reports, for both a fresh join
  /// and a [reconnect].
  ///
  /// Doing this on join is what lets a late joiner (or a player whose socket
  /// dropped) land in the phase the room is actually in: without it the client
  /// sits in the lobby until the *next* socket event happens to arrive, which
  /// mid-reveal can be seconds away and at the end of the game never comes.
  void _applySnapshot(RoomSnapshot snapshot) {
    _mergeRoster(snapshot.players);
    roundSeconds = snapshot.roundSeconds;
    totalRounds = snapshot.totalRounds;
    // The host reads the mode back off the snapshot too, rather than
    // trusting what it asked for, so every client agrees on one source.
    hardcore = snapshot.hardcore;

    final round = snapshot.round;
    if (round != null) {
      roundIndex = round.index;
      currentPhoto = round.photo;
      roundEndsAt = round.endsAt;
      hasGuessedThisRound = round.hasGuessed;
      // Only present once the round is revealed; while it is live the server
      // withholds it, since it is the answer being guessed.
      revealedOwnerId = round.photo.ownerId;
    }

    switch (snapshot.state) {
      case 'in_round':
        phase = GamePhase.inRound;
      case 'revealing':
        phase = GamePhase.revealed;
      case 'finished':
        // Rankings ride in on the roster: the snapshot carries every player's
        // final score, so there is no separate results payload to wait for.
        _finalRankings = [..._players]
          ..sort((a, b) => b.score.compareTo(a.score));
        phase = GamePhase.finished;
      default:
        phase = GamePhase.lobby;
    }
  }

  /// Folds a server snapshot into the live roster.
  ///
  /// The snapshot wins for players in both (fresher scores and photo counts),
  /// and anyone learned only from an event that raced the snapshot is kept.
  void _mergeRoster(List<GamePlayer> fromServer) {
    final seen = <String>{};
    final merged = <GamePlayer>[];
    for (final p in fromServer) {
      if (seen.add(p.id)) merged.add(p);
    }
    for (final p in _players) {
      if (seen.add(p.id)) merged.add(p);
    }
    _players
      ..clear()
      ..addAll(merged);
  }

  Future<void> _teardownSocket() async {
    // Also drops any pending retry: leaving or being kicked must not have a
    // timer reconnect us to a room we are no longer in.
    _heartbeat?.cancel();
    _retryTimer?.cancel();
    _heartbeat = null;
    _retryTimer = null;
    await _sub?.cancel();
    await _socket?.close();
    _sub = null;
    _socket = null;
  }

  void _connectSocket() {
    final s = session;
    _socket = _socketFactory(s.roomCode, s.playerId);
    _sub = _socket!.events.listen(
      (event) {
        _sawFrame = true;
        _onEvent(event);
      },
      onError: (Object e) => _setConnectionError('Connection error: $e'),
      onDone: () => _setConnectionError('Lost connection to the game'),
    );
    _sawFrame = true;
    if (heartbeatInterval > Duration.zero) {
      _heartbeat = Timer.periodic(heartbeatInterval, (_) => _beat());
    }
  }

  /// One heartbeat tick: a silent interval means the socket is dead.
  ///
  /// A mobile connection that vanishes often delivers neither onDone nor
  /// onError, so "nothing came back since the last ping" is the only signal
  /// there is. The `pong` decodes to an [UnknownEvent] and is discarded — it
  /// only has to arrive, not to mean anything.
  void _beat() {
    if (!_sawFrame) {
      _setConnectionError('Lost connection to the game');
      return;
    }
    _sawFrame = false;
    _socket?.ping();
  }

  void _setConnectionError(String message) {
    // The heartbeat and onDone can both fire for one outage; the first wins
    // and the retry chain must not be restarted underneath itself.
    if (connectionError != null) return;
    connectionError = message;
    _heartbeat?.cancel();
    _heartbeat = null;
    _scheduleRetry();
    notifyListeners();
  }

  /// Queues the next automatic retry, if any are left.
  ///
  /// Bounded on purpose: when the backoff list is spent the banner stays up and
  /// the player's manual RETRY is the fallback. An endless silent retry loop is
  /// worse than a visible failure.
  void _scheduleRetry() {
    if (_retriesUsed >= retryBackoff.length) return;
    final delay = retryBackoff[_retriesUsed++];
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      try {
        await reconnect();
      } catch (_) {
        // Still down. `reconnect` left the error set, so queue the next one.
        _scheduleRetry();
        notifyListeners();
      }
    });
  }

  /// Re-open the socket and re-sync from the server.
  ///
  /// The snapshot refetch is mandatory, not an optimisation: events that fired
  /// while we were disconnected are gone, so replaying server state is the
  /// only way back into sync.
  Future<void> reconnect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _teardownSocket();
    // Clear before reconnecting so a socket that drops again immediately can
    // set a fresh error rather than being swallowed as a duplicate.
    connectionError = null;
    _connectSocket();
    try {
      _applySnapshot(await api.getRoom(session.roomCode, playerId: myPlayerId));
    } catch (_) {
      // The room is unreachable, so the new socket is no better than the old.
      await _teardownSocket();
      connectionError = 'Lost connection to the game';
      notifyListeners();
      rethrow;
    }
    // The fetch succeeded, so the connection is good even if the fresh
    // socket's stream still had a stale onDone/onError queued up from the
    // subscription this replaced — that signal describes the old connection,
    // not this one.
    connectionError = null;
    _retriesUsed = 0;
    notifyListeners();
  }

  void _onEvent(GameEvent event) {
    switch (event) {
      case PlayerJoined(:final player):
        if (!_players.any((p) => p.id == player.id)) {
          _players.add(player);
        }
      case PlayerLeft(:final playerId, :final kicked, :final players):
        _players
          ..clear()
          ..addAll(players);
        if (playerId == myPlayerId) {
          // We're the one who's gone: stop listening rather than sit on a feed
          // for a room we're no longer in.
          hasLeftRoom = true;
          removedFromRoom = kicked ? 'The host removed you from the room' : null;
          _teardownSocket();
        } else {
          // Removing a player can hand the host role on, so re-read it from
          // the fresh roster instead of trusting the join-time value.
          final s = _session;
          if (s != null) {
            _session = GameSession(
              roomCode: s.roomCode,
              playerId: s.playerId,
              isHost: _playerById(s.playerId)?.isHost ?? s.isHost,
            );
          }
        }
      case RoundStarted(:final roundIndex, :final photo, :final roundEndsAt):
        this.roundIndex = roundIndex;
        currentPhoto = photo;
        this.roundEndsAt = roundEndsAt;
        revealedOwnerId = null;
        hasGuessedThisRound = false;
        lastPointsEarned = null;
        phase = GamePhase.inRound;
      case RoundRevealed(:final ownerId, :final standings):
        revealedOwnerId = ownerId;
        roundEndsAt = null;
        _standings = standings;
        phase = GamePhase.revealed;
      case GuessResult(:final guesserId, :final points):
        if (guesserId == myPlayerId) {
          lastPointsEarned = points;
        }
        // Scores are broadcast per guess, so keep the live list in step —
        // otherwise the in-game score badge reads 0 for the whole game.
        final i = _players.indexWhere((p) => p.id == guesserId);
        if (i != -1) {
          _players[i] = _players[i].copyWith(score: _players[i].score + points);
        }
      case PhotosUpdated(:final players):
        _players
          ..clear()
          ..addAll(players);
      case SettingsUpdated(
          :final totalRounds,
          :final roundSeconds,
          :final hardcore
        ):
        this.totalRounds = totalRounds;
        this.roundSeconds = roundSeconds;
        this.hardcore = hardcore;
      case GameFinished(:final rankings):
        _finalRankings = rankings;
        phase = GamePhase.finished;
      case RoomReset(:final players):
        _players
          ..clear()
          ..addAll(players);
        roundIndex = 0;
        currentPhoto = null;
        roundEndsAt = null;
        revealedOwnerId = null;
        hasGuessedThisRound = false;
        lastPointsEarned = null;
        _standings = const [];
        _finalRankings = const [];
        phase = GamePhase.lobby;
      case UnknownEvent():
        break;
    }
    notifyListeners();
  }

  /// Batch-uploads photos for the local player. Each image is sent as its own
  /// multipart call because the backend accepts one photo per request.
  ///
  /// A photo that fails is skipped rather than aborting the batch: these are
  /// full-resolution camera-roll originals, and one oversized asset shouldn't
  /// cost the player the rest of their set. Returns how many landed.
  Future<int> uploadPhotos(List<Uint8List> photos) async {
    final s = session;
    var uploaded = 0;
    for (var i = 0; i < photos.length; i++) {
      try {
        await api.uploadPhoto(
          s.roomCode,
          s.playerId,
          photos[i],
          filename: 'photo_$i',
        );
        uploaded++;
      } on Exception {
        // Skip this one; the rest of the batch still counts.
      }
    }
    return uploaded;
  }

  /// True once anyone in the room has contributed a photo. Hardcore mode is
  /// locked from here on (the server enforces it too).
  bool get anyPhotosUploaded => _players.any((p) => p.hasPhotos);

  /// Host changes the lobby settings. Only the fields passed are changed; the
  /// resulting `settings_updated` broadcast is what updates local state.
  Future<void> updateSettings({
    int? totalRounds,
    int? roundSeconds,
    bool? hardcore,
  }) =>
      api.updateSettings(
        session.roomCode,
        hostId: session.playerId,
        totalRounds: totalRounds,
        roundSeconds: roundSeconds,
        hardcore: hardcore,
      );

  /// Host starts the game with the room's configured settings.
  Future<void> startGame({int? totalRounds, int? roundSeconds}) async {
    final rounds = totalRounds ?? this.totalRounds;
    final seconds = roundSeconds ?? this.roundSeconds;
    await api.startGame(
      session.roomCode,
      hostId: session.playerId,
      totalRounds: rounds,
      roundSeconds: seconds,
    );
    this.totalRounds = rounds;
    this.roundSeconds = seconds;
  }

  /// Leave the room, removing this player for everyone.
  ///
  /// The socket is torn down here rather than waiting for our own
  /// `player_left` to come back: the server may well close the feed first, and
  /// that would otherwise surface as a "lost connection" banner on the way out.
  Future<void> leaveRoom() async {
    final s = session;
    hasLeftRoom = true;
    notifyListeners();
    try {
      await api.leaveRoom(s.roomCode, playerId: s.playerId);
    } finally {
      await _teardownSocket();
    }
  }

  /// Host removes another player from the room.
  Future<void> kickPlayer(String playerId) =>
      api.kickPlayer(session.roomCode, hostId: session.playerId, playerId: playerId);

  /// Host resets the room back to the lobby so the same group can play again.
  Future<void> resetRoom() =>
      api.resetRoom(session.roomCode, hostId: session.playerId);

  /// Submit a guess for the current round.
  ///
  /// The lock is applied optimistically so the UI can respond immediately, and
  /// rolled back if the call fails — otherwise a transient error would lock the
  /// player out of the round with no way to retry.
  Future<void> guess(String guessedOwnerId) async {
    if (hasGuessedThisRound) return;
    hasGuessedThisRound = true;
    notifyListeners();
    try {
      await api.submitGuess(
        session.roomCode,
        guesserId: session.playerId,
        guessedOwnerId: guessedOwnerId,
        roundIndex: roundIndex,
      );
    } catch (_) {
      hasGuessedThisRound = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Set once the owner has asked for teardown; see [dispose].
  bool _disposeRequested = false;

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    // The screen that just let go may have been the last one holding this
    // controller open past a requested teardown.
    if (_disposeRequested && !hasListeners) dispose();
  }

  /// Tears down the connections and the notifier — once no screen needs it.
  ///
  /// The owner (`HomeScreen`) disposes when its awaited `Navigator.push`
  /// resolves. But `pushReplacement` *completes the route it replaces*, so
  /// that await also fires in the middle of a lobby -> game hand-off (and
  /// game -> results, and results -> lobby on rematch). Disposing there killed
  /// a controller the incoming screen was already listening to: the
  /// "GameController was used after being disposed" crash on game start.
  ///
  /// So teardown is deferred while any screen is still listening, and runs
  /// from [removeListener] as soon as the last one lets go. Deferring rather
  /// than skipping is what keeps the WebSocket and http.Client from leaking a
  /// connection per game.
  @override
  void dispose() {
    _disposeRequested = true;
    if (hasListeners) return;
    // Every timer dies here. A surviving heartbeat leaks one timer per game,
    // and a surviving retry would call reconnect() on a disposed controller --
    // exactly the "used after being disposed" crash TASK-46 fixed.
    _heartbeat?.cancel();
    _retryTimer?.cancel();
    _heartbeat = null;
    _retryTimer = null;
    // Cancel before closing: a cancelled subscription never delivers onDone,
    // so normal teardown can't trip the connection-lost banner.
    _sub?.cancel();
    _socket?.close();
    api.close();
    super.dispose();
  }
}
