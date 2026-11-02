import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_buttons.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/player_avatar.dart';
import '../ui/player_cosmetics.dart';
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

  /// The result in one line. A tie or a scoreless game is called what it is,
  /// because the top of the list isn't a winner in either.
  String get _headline {
    final ranked = _ranked;
    if (ranked.isEmpty || ranked.first.score == 0) return 'No points this time';
    if (ranked.length > 1 && ranked[1].score == ranked.first.score) {
      return "It's a tie!";
    }
    return '${ranked.first.name} wins!';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: colors.brand,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Text(
                  _headline,
                  style: text.displaySmall!.copyWith(color: colors.ink),
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
                  SecondaryButton(
                    label: 'Leave game',
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
            SizedBox(
              width: 28,
              child: Text('$rank', style: text.titleMedium),
            ),
            PlayerAvatar(
              name: player.name,
              ink: controller.players.inkOf(player.id),
            ),
          ],
        ),
      ),
      title: Text(player.name, style: text.titleMedium),
      subtitle: isMe ? const Text('You') : null,
      trailing: Text('${player.score} points', style: text.titleMedium),
    );
  }
}
