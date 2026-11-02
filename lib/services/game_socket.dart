import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models/game_models.dart';

/// Opens a live game socket. Injected into [GameController] so tests can
/// substitute a fake without touching the network.
typedef GameSocketFactory = GameSocket Function(String code, String playerId);

/// Wraps the game WebSocket and exposes a typed [Stream] of [GameEvent]s.
///
/// Connect with a room code and the player's id; the backend pushes events
/// (player_joined, round_started, round_revealed, guess_result, game_finished,
/// room_reset) which we decode into [GameEvent] objects.
class GameSocket {
  final WebSocketChannel _channel;

  GameSocket._(this._channel);

  factory GameSocket.connect(String code, String playerId) {
    final channel = WebSocketChannel.connect(
      Uri.parse('$wsBase/ws/$code/$playerId'),
    );
    // A failed connection is reported on the stream, which is where the
    // controller handles it. Left alone, this future would also report it as
    // an unhandled exception.
    channel.ready.ignore();
    return GameSocket._(channel);
  }

  /// Decoded events from the server.
  ///
  /// Non-text frames are filtered out rather than throwing: the backend only
  /// ever sends JSON text, so a binary frame is noise, not a fatal error.
  Stream<GameEvent> get events => _channel.stream
      .where((raw) => raw is String)
      .map((raw) => GameEvent.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          ));

  /// Sends a heartbeat. The backend answers with a `pong` frame, which is what
  /// lets the client tell a live socket from a silently dead one — on mobile a
  /// vanished network often produces neither onDone nor onError.
  void ping() => _channel.sink.add('{"type":"ping"}');

  Future<void> close() => _channel.sink.close();
}
