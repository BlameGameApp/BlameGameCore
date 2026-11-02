import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_buttons.dart';
import '../ui/confetti.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/player_cosmetics.dart';
import '../ui/player_token.dart';
import 'lobby_screen.dart';

class ResultsScreen extends StatefulWidget {
  final GameController controller;
  const ResultsScreen({super.key, required this.controller});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with GameControllerScreen<ResultsScreen> {
  @override
  GameController get controller => widget.controller;
  bool _resetting = false;

  List<GamePlayer> get _ranked => controller.finalRankings;

  @override
  bool onControllerChange() {
    // Any player (not just the host who triggered it) lands back in the
    // lobby once the backend confirms the reset over the WebSocket.
    // Everything else just rebuilds: without that the leaderboard is a frozen
    // snapshot and late-arriving results never render.
    if (controller.phase != GamePhase.lobby) return false;
    return navigateOnce(() {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LobbyScreen(controller: controller)),
      );
    });
  }

  Future<void> _startNewRound() async {
    setState(() => _resetting = true);
    try {
      await controller.resetRoom();
      // Navigation happens in onControllerChange once room_reset arrives.
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetting = false);
      snack('Could not start new round: ${friendlyError(e)}');
    }
  }

  /// Leave the room for real. Going back to home alone would leave this player
  /// sitting in it, and a host who did that would strand everyone else on
  /// "Waiting for the host". The server hands the role on when they go. We pop
  /// regardless: the player asked to go, so a failed call shouldn't trap them.
  Future<void> _leave() async {
    try {
      await controller.leaveRoom();
    } catch (_) {
      // Ignored on purpose -- see above.
    }
    if (mounted) {
      navigateOnce(
        () => Navigator.of(context).popUntil((route) => route.isFirst),
      );
    }
  }

  /// The one player who outright won, if anybody did: a tie or a scoreless
  /// game has no winner to celebrate, and the top of the list isn't one.
  GamePlayer? get _winner {
    final ranked = _ranked;
    if (ranked.isEmpty || ranked.first.score == 0) return null;
    if (ranked.length > 1 && ranked[1].score == ranked.first.score) return null;
    return ranked.first;
  }

  String get _headline {
    final winner = _winner;
    if (winner != null) {
      return winner.id == controller.myPlayerId
          ? 'You win!'
          : '${winner.name} wins!';
    }
    return _ranked.isEmpty || _ranked.first.score == 0
        ? 'Nobody scored!'
        : "It's a tie!";
  }

  /// A joke title for the two ends of the leaderboard.
  String? _title(GamePlayer player, int rank) {
    if (player.id == _winner?.id) return 'Top detective';
    final last = rank == _ranked.length;
    return last && player.score < _ranked.first.score ? 'Prime suspect' : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final winner = _winner;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colors.brand,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                children: [
                  if (winner != null) ...[
                    // On white, because the header is the brand colour and so
                    // is the first seat's piece.
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colors.paper,
                      child: PlayerToken(
                        name: winner.name,
                        piece: controller.players.pieceOf(winner.id),
                        radius: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      _headline,
                      style: text.displaySmall!.copyWith(color: colors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _ranked.length,
            itemBuilder: (context, i) => _row(_ranked[i], i + 1),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.isHost) ...[
                  PrimaryButton(
                    label: 'Play again',
                    onPressed: _startNewRound,
                    busy: _resetting,
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text(
                    'Waiting for the host to start a new game',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                SecondaryButton(label: 'Leave game', onPressed: _leave),
              ],
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      body: winner == null
          ? page
          : Stack(fit: StackFit.expand, children: [page, const Confetti()]),
    );
  }

  Widget _row(GamePlayer player, int rank) {
    final text = Theme.of(context).textTheme;
    final isMe = player.id == controller.myPlayerId;
    return ListTile(
      leading: SizedBox(
        width: 72,
        child: Row(
          children: [
            SizedBox(width: 28, child: Text('$rank', style: text.titleMedium)),
            PlayerToken(
              name: player.name,
              piece: controller.players.pieceOf(player.id),
            ),
          ],
        ),
      ),
      title: Text(player.name, style: text.titleMedium),
      subtitle: switch ((isMe, _title(player, rank))) {
        (true, final title?) => Text('You, ${title.toLowerCase()}'),
        (true, null) => const Text('You'),
        (false, final title?) => Text(title),
        (false, null) => null,
      },
      trailing: Text('${player.score} points', style: text.titleMedium),
    );
  }
}
