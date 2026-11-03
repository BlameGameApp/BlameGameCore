/// A player as reported by the backend.
///
/// Pure Dart: colours and avatars are not part of the wire contract, they're
/// derived client-side by the `PlayerCosmetics` extension in lib/ui/.
class GamePlayer {
  final String id;
  final String name;
  final int score;
  final bool isHost;

  /// How many photos this player has contributed. Drives the lobby's ready
  /// state; absent from ranking payloads, where it defaults to 0.
  final int photoCount;

  const GamePlayer({
    required this.id,
    required this.name,
    this.score = 0,
    this.isHost = false,
    this.photoCount = 0,
  });

  /// True once this player has contributed at least one photo.
  bool get hasPhotos => photoCount > 0;

  factory GamePlayer.fromJson(Map<String, dynamic> json) => GamePlayer(
        id: json['id'] as String,
        name: json['name'] as String,
        score: (json['score'] as num?)?.toInt() ?? 0,
        isHost: json['is_host'] as bool? ?? false,
        photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
      );

  GamePlayer copyWith({
    String? name,
    int? score,
    bool? isHost,
    int? photoCount,
  }) =>
      GamePlayer(
        id: id,
        name: name ?? this.name,
        score: score ?? this.score,
        isHost: isHost ?? this.isHost,
        photoCount: photoCount ?? this.photoCount,
      );

  @override
  bool operator ==(Object other) =>
      other is GamePlayer &&
      other.id == id &&
      other.name == name &&
      other.score == score &&
      other.isHost == isHost &&
      other.photoCount == photoCount;

  @override
  int get hashCode => Object.hash(id, name, score, isHost, photoCount);

  @override
  String toString() => 'GamePlayer($id, $name, score: $score, host: $isHost)';
}

/// A photo reference from the backend (URL is relative to [apiBase]).
class PhotoInfo {
  final String id;
  /// Null while the round is still live: the owner *is* the answer, so the
  /// room snapshot withholds it until the round is revealed. Nothing in the UI
  /// reads it — the reveal comes from `round_revealed` — so this stays absent
  /// rather than being faked with a placeholder id.
  final String? ownerId;
  final String url;

  const PhotoInfo({required this.id, this.ownerId, required this.url});

  factory PhotoInfo.fromJson(Map<String, dynamic> json) => PhotoInfo(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String?,
        url: json['url'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PhotoInfo &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.url == url;

  @override
  int get hashCode => Object.hash(id, ownerId, url);
}

/// Base type for events pushed over the WebSocket. We decode by the `type`
/// field into one of the concrete subclasses below.
sealed class GameEvent {
  const GameEvent();

  factory GameEvent.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'player_joined':
        return PlayerJoined(
          GamePlayer.fromJson(json['player'] as Map<String, dynamic>),
        );
      case 'player_left':
        return PlayerLeft(
          playerId: json['player_id'] as String,
          kicked: json['kicked'] as bool? ?? false,
          players: (json['players'] as List<dynamic>)
              .map((e) => GamePlayer.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'round_started':
        return RoundStarted(
          roundIndex: (json['round_index'] as num).toInt(),
          photo: PhotoInfo.fromJson(json['photo'] as Map<String, dynamic>),
          roundEndsAt: (json['round_ends_at'] as num).toInt(),
        );
      case 'round_revealed':
        return RoundRevealed(
          roundIndex: (json['round_index'] as num).toInt(),
          ownerId: json['owner_id'] as String,
          standings: ((json['standings'] as List<dynamic>?) ?? const [])
              .map((e) => GamePlayer.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'guess_result':
        return GuessResult(
          guesserId: json['guesser_id'] as String,
          points: (json['points'] as num).toInt(),
          correct: json['correct'] as bool,
        );
      case 'game_finished':
        return GameFinished(
          (json['rankings'] as List<dynamic>)
              .map((e) => GamePlayer.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'photos_updated':
        return PhotosUpdated(
          (json['players'] as List<dynamic>)
              .map((e) => GamePlayer.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      case 'settings_updated':
        return SettingsUpdated(
          totalRounds: (json['total_rounds'] as num).toInt(),
          roundSeconds: (json['round_seconds'] as num).toInt(),
          hardcore: json['hardcore'] as bool,
        );
      case 'room_reset':
        return RoomReset(
          (json['players'] as List<dynamic>)
              .map((e) => GamePlayer.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      default:
        return UnknownEvent(json['type'] as String);
    }
  }
}

class PlayerJoined extends GameEvent {
  final GamePlayer player;
  const PlayerJoined(this.player);
}

/// Someone left or was kicked: carries the refreshed roster, since removing a
/// player can also hand the host role to someone else.
class PlayerLeft extends GameEvent {
  final String playerId;
  final bool kicked;
  final List<GamePlayer> players;
  const PlayerLeft({
    required this.playerId,
    required this.kicked,
    required this.players,
  });
}

class RoundStarted extends GameEvent {
  final int roundIndex;
  final PhotoInfo photo;
  /// Server epoch-ms deadline for this round; clients derive remaining time
  /// as `roundEndsAt - now()` instead of running their own local clock.
  final int roundEndsAt;
  const RoundStarted({
    required this.roundIndex,
    required this.photo,
    required this.roundEndsAt,
  });
}

class RoundRevealed extends GameEvent {
  final int roundIndex;
  final String ownerId;

  /// Standings after this round, already ordered by the server. Rendered
  /// as-is: scoring is server-authoritative, so the client never re-sorts.
  final List<GamePlayer> standings;

  const RoundRevealed({
    required this.roundIndex,
    required this.ownerId,
    this.standings = const [],
  });
}

class GuessResult extends GameEvent {
  final String guesserId;
  final int points;
  final bool correct;
  const GuessResult({
    required this.guesserId,
    required this.points,
    required this.correct,
  });
}

class GameFinished extends GameEvent {
  final List<GamePlayer> rankings;
  const GameFinished(this.rankings);
}

/// Someone uploaded a photo: carries the refreshed roster so the lobby can
/// show who is ready.
class PhotosUpdated extends GameEvent {
  final List<GamePlayer> players;
  const PhotosUpdated(this.players);
}

/// The host changed the game settings in the lobby. Broadcast to everyone, so
/// non-hosts see what they are about to play.
class SettingsUpdated extends GameEvent {
  final int totalRounds;
  final int roundSeconds;
  final bool hardcore;
  const SettingsUpdated({
    required this.totalRounds,
    required this.roundSeconds,
    required this.hardcore,
  });
}

class RoomReset extends GameEvent {
  final List<GamePlayer> players;
  const RoomReset(this.players);
}

class UnknownEvent extends GameEvent {
  final String type;
  const UnknownEvent(this.type);
}
