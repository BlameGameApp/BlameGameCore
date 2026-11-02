import 'dart:async';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/band.dart';
import '../ui/connection_banner.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/fit_text.dart';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PosterScaffold(
      top: colors.ink,
      body: Column(
        children: [
          _topBar(),
          ConnectionBanner(controller: c),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final panel = _panelHeight();
                return Stack(
                  children: [
                    Positioned.fill(bottom: panel, child: _photoArea()),
                    if (c.phase == GamePhase.inRound)
                      Positioned(
                        right: 0,
                        bottom: panel,
                        child: _countdown(),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: panel,
                      child: c.hasGuessedThisRound
                          ? _lockedIn()
                          : _guessGrid(panel),
                    ),
                    if (c.phase == GamePhase.revealed)
                      _reveal(box.maxHeight * 0.52),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final colors = context.colors;
    final progress = c.roundSeconds == 0 ? 0.0 : _timeLeft / c.roundSeconds;
    final text = uiText(15, weight: 700, color: colors.paper);
    return Column(
      children: [
        Band(
          color: colors.ink,
          padding: EdgeInsets.fromLTRB(
            bandGutter,
            MediaQuery.paddingOf(context).top + 4,
            bandGutter,
            12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Round ${c.roundIndex + 1} of ${c.totalRounds}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text,
                ),
              ),
              const SizedBox(width: 12),
              Text('${c.me?.score ?? 0} points', style: text),
            ],
          ),
        ),
        // The whole round is this one bar running out. Animated over the tick
        // so it drains instead of stepping once a second.
        ColoredBox(
          color: colors.ink,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(seconds: 1),
              widthFactor: c.phase == GamePhase.inRound ? progress : 0,
              child: Container(
                height: 8,
                color: _timeLeft <= 3 ? colors.vermilion : colors.marigold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _countdown() {
    final colors = context.colors;
    final urgent = _timeLeft <= 3;
    return Semantics(
      label: '$_timeLeft seconds left',
      child: ExcludeSemantics(
        child: Container(
          color: urgent ? colors.vermilion : colors.ink,
          width: 96,
          height: 72,
          padding: const EdgeInsets.all(14),
          child: Center(
            child: FitText(
              '$_timeLeft',
              color: urgent ? colors.ink : colors.paper,
            ),
          ),
        ),
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
    final waiting = Center(child: CircularProgressIndicator(color: colors.paper));
    return ColoredBox(
      color: colors.ink,
      child: photo == null
          ? waiting
          : Image.network(
              '$apiBase${photo.url}',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: decodeWidth,
              semanticLabel: 'Photo for round ${c.roundIndex + 1}',
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.broken_image,
                  color: colors.paperMuted,
                  size: 64,
                ),
              ),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : waiting,
            ),
    );
  }

  /// Taller as the room fills, so names stay big enough to hit under a
  /// countdown. The bottom row runs under the home indicator.
  double _panelHeight() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rows = _rowsOf(c.players.length);
    return (rows * 64.0 < 200 ? 200.0 : rows * 64.0) + bottom;
  }

  /// One column while names can stay huge, more once a stack would be too
  /// thin to tap. The room caps at 12, which is 3 x 4.
  int _columnsFor(int players) {
    if (players <= 4) return 1;
    return players <= 8 ? 2 : 3;
  }

  int _rowsOf(int players) {
    if (players == 0) return 1;
    return (players / _columnsFor(players)).ceil();
  }

  Widget _guessGrid(double panel) {
    // You guess who took the photo — any player, including yourself, is a candidate.
    final candidates = c.players;
    final columns = _columnsFor(candidates.length);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rows = <List<GamePlayer>>[
      for (var i = 0; i < candidates.length; i += columns)
        candidates.skip(i).take(columns).toList(),
    ];
    final rowHeight = (panel - bottom) / rows.length;
    return Column(
      children: [
        for (final (i, row) in rows.indexed)
          SizedBox(
            height: i == rows.length - 1 ? rowHeight + bottom : rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final player in row)
                  Expanded(
                    child: _guessBand(
                      player,
                      bottomInset: i == rows.length - 1 ? bottom : 0,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _guessBand(GamePlayer player, {required double bottomInset}) {
    final colors = context.colors;
    final disabled = _timeExpired || c.phase != GamePhase.inRound;
    return PlayerBand(
      name: player.name,
      ink: disabled
          ? PlayerInk(colors.ink, colors.paperMuted)
          : c.players.inkOf(player.id),
      actionLabel: 'Guess ${player.name}',
      bottomInset: bottomInset,
      onTap: disabled ? null : () => _guess(player),
    );
  }

  /// After a guess the panel becomes the one band that was picked, which is
  /// also where a correct answer is announced. A wrong one only says it landed:
  /// the owner isn't known until the reveal.
  Widget _lockedIn() {
    final points = c.lastPointsEarned;
    final guessed = c.players.where((p) => p.id == _myGuessedPlayerId);
    return PlayerBand(
      name: guessed.isEmpty ? 'Locked in' : guessed.first.name,
      ink: c.players.inkOf(_myGuessedPlayerId),
      leading: 'You blamed',
      trailing: points == null
          ? null
          : points > 0
          ? 'Correct! +$points points'
          : 'Guess submitted',
      bottomInset: MediaQuery.paddingOf(context).bottom,
    );
  }

  /// The round's one loud moment: the owner's band slams up over the guesses.
  ///
  /// Keyed by round so each reveal runs again, and instant for anyone who asked
  /// the system for reduced motion.
  Widget _reveal(double height) {
    final ink = c.players.inkOf(c.revealedOwnerId);
    final text = uiText(18, weight: 800, color: ink.on);
    final points = c.lastPointsEarned ?? 0;
    final guessed = c.players.where((p) => p.id == _myGuessedPlayerId);
    final String outcome;
    if (points > 0) {
      outcome = 'Correct! +$points points';
    } else if (guessed.isNotEmpty) {
      outcome = 'You blamed ${guessed.first.name}';
    } else if (c.hasGuessedThisRound) {
      outcome = 'Wrong guess';
    } else {
      outcome = 'No guess this round';
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: height,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(c.roundIndex),
        tween: Tween(begin: 1, end: 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutQuart,
        builder: (context, offset, child) => Transform.translate(
          offset: Offset(0, height * offset),
          child: child,
        ),
        child: Band(
          color: ink.fill,
          padding: EdgeInsets.fromLTRB(
            bandGutter,
            16,
            bandGutter,
            MediaQuery.paddingOf(context).bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('It was', style: text),
              const SizedBox(height: 12),
              Expanded(
                child: FitText(
                  c.revealedOwnerName.toUpperCase(),
                  color: ink.on,
                  semanticsLabel: c.revealedOwnerName,
                ),
              ),
              const SizedBox(height: 16),
              Text(outcome, style: text),
            ],
          ),
        ),
      ),
    );
  }
}
