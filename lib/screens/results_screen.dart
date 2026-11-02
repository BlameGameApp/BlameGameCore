import 'package:flutter/material.dart';

import '../models/game_models.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_buttons.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/gradient_scaffold.dart';
import '../ui/player_avatar.dart';
import '../ui/tinted_card.dart';
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
    if (leaveIfRemoved()) return true;
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
    final winner = _ranked.isNotEmpty ? _ranked.first : null;
    final colors = context.colors;

    return GradientScaffold(
      gradient: AppGradient.verticalThreeStop,
      child: Column(
        children: [
          const SizedBox(height: 24),
          _trophy(winner),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text('LEADERBOARD', style: Theme.of(context).textTheme.labelLarge!
                    .copyWith(color: colors.onSurfaceFaint)),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _ranked.length,
              itemBuilder: (context, i) => _tile(_ranked[i], i + 1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                if (controller.isHost) ...[
                  PrimaryButton(
                    label: 'START NEW ROUND',
                    onPressed: _resetting ? null : _startNewRound,
                    color: colors.accent,
                    busy: _resetting,
                  ),
                  const SizedBox(height: 12),
                ],
                PrimaryButton(
                  label: 'BACK TO HOME',
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _trophy(GamePlayer? winner) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The darker end of the trophy gradient is a one-off; it isn't a
            // palette colour, so it stays here rather than bloating AppColors.
            gradient: LinearGradient(
                colors: [colors.gold, const Color(0xFFFFA500)]),
            boxShadow: [
              BoxShadow(
                  color: colors.gold.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 5),
            ],
          ),
          child: Icon(Icons.emoji_events,
              size: 56, color: colors.onSurfaceStrong),
        ),
        const SizedBox(height: 16),
        Text('WINNER',
            style: TextStyle(
                color: colors.gold,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 6)),
        const SizedBox(height: 8),
        // Explicit rather than text.headlineLarge: the theme style resolves to
        // a slightly different line height here and shifts everything below it
        // up ~14pt, which this refactor must not do.
        Text(winner?.name ?? '—',
            style: TextStyle(
                color: colors.onSurfaceStrong,
                fontSize: 36,
                fontWeight: FontWeight.w900)),
        Text('${winner?.score ?? 0} pts',
            style: TextStyle(color: colors.onSurfaceMuted, fontSize: 18)),
      ],
    );
  }

  Widget _tile(GamePlayer player, int rank) {
    final colors = context.colors;
    final medalColor = {
      1: colors.gold,
      2: colors.silver,
      3: colors.bronze,
    }[rank];
    final isMe = player.id == controller.myPlayerId;
    final first = rank == 1;

    return TintedCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      tint: first ? colors.gold : colors.onSurfaceStrong,
      fillAlpha: first ? 0.08 : 0.05,
      borderAlpha: first ? 0.3 : null,
      radius: 14,
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: medalColor != null
                ? Icon(Icons.workspace_premium, color: medalColor, size: 28)
                : Text('#$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: colors.onSurfaceFaint,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          PlayerAvatar(player: player, radius: 20, iconSize: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name,
                    style: TextStyle(
                        color: colors.onSurfaceStrong,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                if (isMe)
                  Text("That's you!",
                      style: TextStyle(
                          color: colors.onSurfaceStrong
                              .withValues(alpha: 0.4),
                          fontSize: 12)),
              ],
            ),
          ),
          Text('${player.score}',
              style: TextStyle(
                  color: first ? colors.gold : colors.onSurfaceStrong,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text('pts',
              style: TextStyle(
                  color: colors.onSurfaceStrong.withValues(alpha: 0.4),
                  fontSize: 12)),
        ],
      ),
    );
  }
}
