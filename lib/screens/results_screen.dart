import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/band.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ranked = _ranked;
    final winnerInk = ranked.isEmpty
        ? PlayerInk(colors.ink, colors.paper)
        : controller.players.inkOf(ranked.first.id);
    return PosterScaffold(
      top: winnerInk.fill,
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => ListView.builder(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: ranked.length,
                itemBuilder: (context, i) => SizedBox(
                  height: _bandHeight(ranked[i], ranked, box.maxHeight),
                  child: _band(ranked[i], i),
                ),
              ),
            ),
          ),
          if (controller.isHost)
            BandButton(
              label: _resetting ? 'Starting…' : 'Play again',
              onPressed: _resetting ? null : _startNewRound,
              color: colors.paper,
              textColor: colors.ink,
              busy: _resetting,
            ),
          BandButton(
            label: 'Leave game',
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            color: colors.ink,
            textColor: colors.paper,
            last: true,
          ),
        ],
      ),
    );
  }

  /// The leaderboard is drawn to scale: every band gets a floor, and the room
  /// left over is shared out by score. Winning takes up the poster.
  double _bandHeight(GamePlayer player, List<GamePlayer> ranked, double room) {
    final top = MediaQuery.paddingOf(context).top;
    const floor = 84.0;
    final spare = room - top - ranked.length * floor;
    final extra = player == ranked.first ? top : 0.0;
    if (spare <= 0) return floor + extra;
    final total = ranked.fold<int>(0, (sum, p) => sum + p.score);
    final share = total == 0 ? 1 / ranked.length : player.score / total;
    return floor + spare * share + extra;
  }

  Widget _band(GamePlayer player, int rank) {
    final isMe = player.id == controller.myPlayerId;
    return PlayerBand(
      name: player.name,
      ink: controller.players.inkOf(player.id),
      leading: isMe ? '${rank + 1}. You' : '${rank + 1}.',
      trailing: '${player.score} points',
      topInset: rank == 0 ? MediaQuery.paddingOf(context).top : 0,
    );
  }
}
