import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/connection_banner.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/player_avatar.dart';
import '../ui/player_cosmetics.dart';
import 'results_screen.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;
  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with GameControllerScreen<GameScreen> {
  @override
  GameController get controller => widget.controller;
  GameController get c => widget.controller;

  int _timeLeft = 0;
  bool _timeExpired = false;
  Timer? _displayTimer;
  int _shownRound = -1;
  String? _myGuessedPlayerId;

  @override
  void initState() {
    super.initState();
    _syncToRound();
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  @override
  bool onControllerChange() {
    if (c.phase == GamePhase.finished) {
      final left = navigateOnce(() {
        _displayTimer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ResultsScreen(controller: c)),
        );
      });
      if (left) return true;
    }

    // New round started on the backend -> restart the local display countdown.
    if (c.phase == GamePhase.inRound && c.roundIndex != _shownRound) {
      _myGuessedPlayerId = null;
      _syncToRound();
    }

    if (c.phase == GamePhase.revealed) _displayTimer?.cancel();
    return false;
  }

  void _syncToRound() {
    _shownRound = c.roundIndex;
    _timeExpired = false;
    _displayTimer?.cancel();
    _computeTimeLeft();
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(_computeTimeLeft);
    });
    setState(() {});
  }

  /// Derives remaining time from the server's round_ends_at deadline instead
  /// of decrementing a local counter, so a late-arriving round_started event
  /// or a missed tick still lands on the correct remaining time.
  void _computeTimeLeft() {
    final endsAt = c.roundEndsAt;
    final remainingMs = endsAt == null
        ? 0
        : endsAt - DateTime.now().millisecondsSinceEpoch;
    _timeLeft = (remainingMs / 1000).ceil().clamp(0, c.roundSeconds);
    if (_timeLeft <= 0) {
      _timeExpired = true;
      _displayTimer?.cancel();
    }
  }

  Future<void> _guess(GamePlayer player) async {
    if (c.hasGuessedThisRound || _timeExpired || c.phase != GamePhase.inRound) {
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _myGuessedPlayerId = player.id);
    try {
      await c.guess(player.id);
    } on Exception catch (e) {
      // The controller has already released the round lock; clear the local
      // selection too so the player can try again, and say what happened.
      if (!mounted) return;
      setState(() => _myGuessedPlayerId = null);
      snack('Guess failed: ${friendlyError(e)}');
    }
  }

  /// There's no way back into a game once it has started, so leaving is asked
  /// about, and an accidental swipe-back can't do it.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text("You won't be able to rejoin it."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    try {
      await c.leaveRoom();
    } catch (_) {
      // Leaving anyway: the player asked to go, and a failed call shouldn't
      // keep them in a game they've left.
    }
    if (mounted) navigateOnce(() => Navigator.of(context).pop());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConnectionBanner(controller: c),
              _topBar(),
              _timer(),
              const SizedBox(height: 8),
              Expanded(child: _photoArea()),
              _prompt(),
              _guessGrid(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: _confirmLeave,
            tooltip: 'Leave game',
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              'Round ${c.roundIndex + 1} of ${c.totalRounds}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${c.me?.score ?? 0} points',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timer() {
    final colors = context.colors;
    final inRound = c.phase == GamePhase.inRound;
    final progress = c.roundSeconds == 0 ? 0.0 : _timeLeft / c.roundSeconds;
    final urgent = inRound && _timeLeft <= 3;
    final color = urgent ? colors.alert : colors.ink;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ColoredBox(
                color: colors.surface,
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Animated over the tick so it drains instead of stepping
                  // once a second.
                  child: AnimatedFractionallySizedBox(
                    duration: const Duration(seconds: 1),
                    widthFactor: inRound ? progress : 0,
                    child: Container(height: 8, color: color),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Semantics(
              label: '$_timeLeft seconds left',
              child: ExcludeSemantics(
                child: Text(
                  inRound ? '$_timeLeft' : '',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoArea() {
    final photo = c.currentPhoto;
    final colors = context.colors;
    // Uploads are full-resolution camera originals (~4032x3024 = ~48MB
    // decoded). Decoding at display size instead keeps a whole game inside
    // the image cache rather than thrashing it or OOMing on smaller devices.
    final decodeWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final waiting = Center(child: CircularProgressIndicator(color: colors.ink));
    return ColoredBox(
      color: colors.ink,
      child: photo == null
          ? Center(child: CircularProgressIndicator(color: colors.paper))
          : Image.network(
              '$apiBase${photo.url}',
              // The whole picture, not a crop: the clue may be in a corner.
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: decodeWidth,
              semanticLabel: 'Photo for round ${c.roundIndex + 1}',
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.broken_image,
                  color: colors.paper,
                  size: 64,
                ),
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : ColoredBox(color: colors.paper, child: waiting),
            ),
    );
  }

  /// One line that always says where the round stands. It has a fixed height,
  /// so nothing under it moves and the names stay where the thumb already is.
  Widget _prompt() {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final points = c.lastPointsEarned;
    final guessed = c.players.where((p) => p.id == _myGuessedPlayerId);
    final String headline;
    String? detail;
    var color = colors.ink;
    if (c.phase == GamePhase.revealed) {
      headline = "It was ${c.revealedOwnerName}'s photo";
      if ((points ?? 0) > 0) {
        detail = 'Correct! +$points points';
        color = colors.correct;
      } else if (guessed.isNotEmpty) {
        detail = 'You guessed ${guessed.first.name}';
      } else if (c.hasGuessedThisRound) {
        detail = 'Your guess was wrong';
      } else {
        detail = 'No guess this round';
      }
    } else if (c.hasGuessedThisRound) {
      if ((points ?? 0) > 0) {
        headline = 'Correct! +$points points';
        color = colors.correct;
      } else {
        headline = 'Guess submitted';
        detail = 'Waiting for the answer…';
      }
    } else if (_timeExpired) {
      headline = "Time's up";
    } else {
      headline = 'Whose photo is this?';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SizedBox(
        height: 54,
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: text.titleMedium!.copyWith(
                  color: color,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail != null)
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: text.bodyMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guessGrid() {
    // You guess who took the photo — any player, including yourself, is a candidate.
    final candidates = c.players;
    // Two columns keep a 24-character name readable. Three is only for a room
    // so full that two would squeeze the photo to nothing.
    final columns = candidates.length > 8 ? 3 : 2;
    final rows = <List<GamePlayer>>[
      for (var i = 0; i < candidates.length; i += columns)
        candidates.skip(i).take(columns).toList(),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                children: [
                  for (final (j, player) in row.indexed) ...[
                    if (j > 0) const SizedBox(width: 8),
                    Expanded(child: _guessButton(player, compact: columns == 3)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The same button from the first second to the reveal: only its state
  /// changes, so the player's eye never has to find anything twice. Each state
  /// also carries an icon, because red and green alone don't reach everyone.
  Widget _guessButton(GamePlayer player, {required bool compact}) {
    final colors = context.colors;
    final revealed = c.phase == GamePhase.revealed;
    final disabled = c.hasGuessedThisRound || _timeExpired || revealed;
    final picked = player.id == _myGuessedPlayerId;
    final isOwner = revealed && player.id == c.revealedOwnerId;

    var fill = colors.surface;
    var foreground = disabled ? colors.muted : colors.ink;
    IconData? icon;
    if (isOwner) {
      fill = colors.correct;
      foreground = colors.paper;
      icon = Icons.check;
    } else if (revealed && picked) {
      fill = colors.alert;
      foreground = colors.paper;
      icon = Icons.close;
    } else if (picked) {
      fill = colors.ink;
      foreground = colors.paper;
    }

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'Guess ${player.name}',
      onTap: disabled ? null : () => _guess(player),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : () => _guess(player),
          excludeFromSemantics: true,
          child: ExcludeSemantics(
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 52 : 56),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: 6,
              ),
              child: Row(
                children: [
                  if (!compact) ...[
                    PlayerAvatar(
                      name: player.name,
                      ink: c.players.inkOf(player.id),
                      radius: 16,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      player.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: compact ? TextAlign.center : TextAlign.start,
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.2),
                      style: TextStyle(
                        color: foreground,
                        fontSize: compact ? 14 : 16,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (icon != null) Icon(icon, color: foreground, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
