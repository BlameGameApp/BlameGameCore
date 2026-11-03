import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/connection_banner.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/gradient_scaffold.dart';
import '../ui/pill_badge.dart';
import '../ui/result_banner.dart';
import '../ui/player_cosmetics.dart';
import 'results_screen.dart';

class GameScreen extends StatefulWidget {
  final GameController controller;
  const GameScreen({super.key, required this.controller});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, GameControllerScreen<GameScreen> {
  @override
  GameController get controller => widget.controller;
  GameController get c => widget.controller;

  int _timeLeft = 0;
  bool _timeExpired = false;
  Timer? _displayTimer;
  int _shownRound = -1;
  String? _myGuessedPlayerId;
  GamePhase? _lastPhase;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _syncToRound();
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    _shakeController.dispose();
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

    // Round revealed -> stop the timer, shake if we were wrong. Gate on the
    // transition: _onChange fires for every event, including other players'
    // results, and the banner shouldn't re-shake each time one lands.
    if (c.phase == GamePhase.revealed && _lastPhase != GamePhase.revealed) {
      _displayTimer?.cancel();
      final wrong = c.hasGuessedThisRound && (c.lastPointsEarned ?? 0) == 0;
      if (wrong) _shakeController.forward(from: 0);
    }
    _lastPhase = c.phase;
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
    return GradientScaffold(
      gradient: AppGradient.verticalTwoStop,
      child: Column(
        children: [
          ConnectionBanner(controller: c),
          _topBar(),
          const SizedBox(height: 8),
          _timerBar(),
          const SizedBox(height: 16),
          Expanded(child: _photoArea()),
          const SizedBox(height: 16),
          if (c.phase == GamePhase.revealed) ...[
            _resultBanner(),
            _standingsStrip(),
          ],
          if (c.phase == GamePhase.inRound && c.hasGuessedThisRound)
            _instantResultBanner(),
          if (c.phase == GamePhase.inRound) _guessButtons(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _topBar() {
    final myScore = c.me?.score ?? 0;
    final colors = context.colors;
    const pillPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 6);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PillBadge(
            color: colors.onSurfaceStrong,
            fillAlpha: 0.1,
            radius: 20,
            padding: pillPadding,
            child: Text(
              'Round ${c.roundIndex + 1}',
              style: TextStyle(
                color: colors.onSurfaceStrong,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PillBadge(
            color: colors.brand,
            radius: 20,
            padding: pillPadding,
            child: Row(
              children: [
                Icon(Icons.star, color: colors.gold, size: 18),
                const SizedBox(width: 4),
                Text(
                  '$myScore',
                  style: TextStyle(
                    color: colors.onSurfaceStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timerBar() {
    final progress = c.roundSeconds == 0 ? 0.0 : _timeLeft / c.roundSeconds;
    final colors = context.colors;
    final color = _timeLeft <= 3 ? colors.brand : colors.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                '$_timeLeft',
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colors.onSurfaceStrong.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoArea() {
    final photo = c.currentPhoto;
    final white = context.colors.onSurfaceStrong;
    // Uploads are full-resolution camera originals (~4032x3024 = ~48MB
    // decoded). Decoding at display size instead keeps a whole game inside
    // the image cache rather than thrashing it or OOMing on smaller devices.
    final decodeWidth =
        ((MediaQuery.sizeOf(context).width - 48) *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.black.withValues(alpha: 0.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: photo == null
          ? Center(child: CircularProgressIndicator(color: white))
          : Image.network(
              '$apiBase${photo.url}',
              fit: BoxFit.cover,
              width: double.infinity,
              cacheWidth: decodeWidth,
              semanticLabel: 'Photo for round ${c.roundIndex + 1}',
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.broken_image,
                  // 54%, not the palette's 50% faint — kept exact so the
                  // refactor stays invisible.
                  color: white.withValues(alpha: 0.54),
                  size: 64,
                ),
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Center(child: CircularProgressIndicator(color: white)),
            ),
    );
  }

  /// Shown right after the local player guesses, before the round reveals
  /// the true owner to everyone. Only reports the player's own result --
  /// no owner name, since that isn't known until the reveal.
  Widget _instantResultBanner() {
    final points = c.lastPointsEarned;
    if (points == null) return const SizedBox.shrink();
    return ResultBanner(
      correct: points > 0,
      message: points > 0 ? 'Correct! +$points points' : 'Guess submitted',
    );
  }

  /// The round reveal: names the owner, and shakes on a wrong guess.
  Widget _resultBanner() {
    final correct = (c.lastPointsEarned ?? 0) > 0;
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final shake = correct ? 0.0 : sin(_shakeAnimation.value * 3 * pi) * 8;
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: ResultBanner(
        correct: correct,
        message: correct
            ? 'Correct! +${c.lastPointsEarned} points'
            : "It was ${c.revealedOwnerName}'s photo",
      ),
    );
  }

  /// Between-rounds scoreboard, shown for the server's reveal hold alongside
  /// the result banner. Rows are rendered in the order the server sent them —
  /// scoring is server-authoritative and the client never re-sorts.
  Widget _standingsStrip() {
    final standings = c.standings;
    if (standings.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < standings.length; i++)
            _standingsRow(standings[i], i + 1, colors),
        ],
      ),
    );
  }

  Widget _standingsRow(GamePlayer player, int rank, AppColors colors) {
    final isMe = player.id == c.myPlayerId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? colors.gold : colors.onSurfaceFaint,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Icon(player.avatar, color: player.color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              player.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurfaceStrong,
                fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${player.score}',
            style: TextStyle(
              color: rank == 1 ? colors.gold : colors.onSurfaceStrong,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guessButtons() {
    // You guess who took the photo — any player, including yourself, is a candidate.
    final candidates = c.players;
    final white = context.colors.onSurfaceStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: candidates.map((player) {
          final disabled = c.hasGuessedThisRound || _timeExpired;
          final isSelected =
              c.hasGuessedThisRound && player.id == _myGuessedPlayerId;
          const radius = BorderRadius.all(Radius.circular(14));
          // One semantics node for the whole chip: the label, the button
          // role and the tap live here, and the icon and text inside are
          // excluded so a screen reader announces the chip once rather than
          // reading out its parts.
          return Semantics(
            button: true,
            enabled: !disabled,
            selected: isSelected,
            label: 'Guess ${player.name}',
            onTap: disabled ? null : () => _guess(player),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected
                    ? player.color
                    : player.color.withValues(alpha: disabled ? 0.05 : 0.15),
                borderRadius: radius,
                border: Border.all(
                  color: player.color.withValues(alpha: isSelected ? 1.0 : 0.3),
                  width: isSelected ? 2 : 1,
                ),
              ),
              // Transparent Material *inside* the container, so the splash is
              // painted above the chip's fill instead of underneath it. The
              // padding moved in with it so the whole chip is the tap target.
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: disabled ? null : () => _guess(player),
                  borderRadius: radius,
                  excludeFromSemantics: true,
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            player.avatar,
                            color: isSelected ? white : player.color,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            player.name,
                            style: TextStyle(
                              color: isSelected
                                  ? white
                                  : white.withValues(alpha: 0.9),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle, color: white, size: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
