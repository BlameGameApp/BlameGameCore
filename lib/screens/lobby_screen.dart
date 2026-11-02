import 'package:flutter/material.dart';

import '../config.dart';
import '../models/game_models.dart';
import '../services/photo_sampler.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_buttons.dart';
import '../ui/connection_banner.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/gradient_scaffold.dart';
import '../ui/pill_badge.dart';
import '../ui/player_avatar.dart';
import '../ui/player_cosmetics.dart';
import '../ui/snack.dart';
import '../ui/tinted_card.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final GameController controller;

  /// Injectable so widget tests can drive the preview without a camera roll.
  final PhotoSampler? sampler;

  const LobbyScreen({super.key, required this.controller, this.sampler});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with GameControllerScreen<LobbyScreen> {
  @override
  GameController get controller => widget.controller;
  GameController get c => widget.controller;
  late final _sampler = widget.sampler ?? PhotoSampler();
  bool _photoUploaded = false;
  bool _uploading = false;

  @override
  bool onControllerChange() {
    if (leaveIfRemoved()) return true;
    // When the backend starts the game, move everyone to the game screen.
    if (c.phase != GamePhase.lobby) {
      return navigateOnce(() {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => GameScreen(controller: c)),
        );
      });
    }
    return false;
  }

  /// Samples random photos and uploads them.
  ///
  /// In normal mode they are shown for confirmation first and nothing leaves
  /// the device before the player says so. In hardcore mode they are uploaded
  /// blind — which is why nothing is sampled at all until the room's mode is
  /// known, and why the lobby states the mode before this button is usable.
  Future<void> _addPhotos() async {
    if (_uploading) return;
    final hardcore = c.hardcore;
    if (hardcore == null) {
      snack('Still loading the game settings — try again in a moment');
      return;
    }
    setState(() => _uploading = true);
    try {
      final photos = await _sampler.sampleRandomPhotos(count: photoSampleCount);
      if (photos.isEmpty) {
        snack('No photos found in your camera roll');
        return;
      }
      if (!mounted) return;
      final List<SampledPhoto> confirmed;
      if (hardcore) {
        // No preview, no reshuffle: what was sampled is what gets shared.
        confirmed = photos;
      } else {
        final chosen = await showModalBottomSheet<List<SampledPhoto>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.colors.bgMid,
          builder: (_) => _PhotoPreviewSheet(sampler: _sampler, initial: photos),
        );
        if (chosen == null || chosen.isEmpty) return;
        confirmed = chosen;
      }
      final uploaded = await c.uploadPhotos([
        for (final p in confirmed) p.bytes,
      ]);
      if (mounted) setState(() => _photoUploaded = true);
      snack('Added $uploaded photo${uploaded == 1 ? '' : 's'}');
    } on PhotoPermissionDenied {
      snack('Photo access denied — enable it in Settings to add photos');
    } catch (e) {
      snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _start() async {
    try {
      await c.startGame();
    } catch (e) {
      snack('Could not start: $e');
    }
  }

  /// Push one setting change. The server answers with a `settings_updated`
  /// broadcast, which is what actually moves local state — so a rejected
  /// change (a hardcore flip after photos landed) simply doesn't take.
  Future<void> _setSetting({
    int? totalRounds,
    int? roundSeconds,
    bool? hardcore,
  }) async {
    try {
      await c.updateSettings(
        totalRounds: totalRounds,
        roundSeconds: roundSeconds,
        hardcore: hardcore,
      );
    } catch (e) {
      snack(friendlyError(e));
    }
  }

  /// Leave the room. We pop regardless: the player asked to go, so a failed
  /// call shouldn't trap them in a lobby they've mentally left.
  Future<void> _leave() async {
    try {
      await c.leaveRoom();
    } catch (_) {
      // Ignored on purpose -- see above.
    }
    if (mounted) navigateOnce(() => Navigator.of(context).pop());
  }

  Future<void> _kick(GamePlayer player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${player.name}?'),
        content: Text("They'll be dropped from the room and lose their photos."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await c.kickPlayer(player.id);
    } catch (e) {
      snack('Could not remove ${player.name}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GradientScaffold(
      gradient: AppGradient.diagonal,
      child: Column(
        children: [
          ConnectionBanner(controller: c),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // IconButton, not a bare GestureDetector: a 24x24 icon is
                // half the 48x48 minimum tap target and carries no button
                // semantics for screen readers.
                IconButton(
                  onPressed: _leave,
                  tooltip: 'Leave room',
                  icon: Icon(
                    Icons.arrow_back_ios,
                    color: colors.onSurfaceStrong,
                  ),
                ),
                Expanded(
                  child: Text(
                    'LOBBY',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 24),
              ],
            ),
          ),
          _gameCode(),
          const SizedBox(height: 12),
          Text(
            'Share this code with friends',
            style: TextStyle(
              color: colors.onSurfaceStrong.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'PLAYERS (${c.players.length})',
            style: TextStyle(
              color: colors.onSurfaceStrong.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: c.players.length,
              itemBuilder: (context, i) => _playerTile(c.players[i]),
            ),
          ),
          _settingsPanel(),
          _bottomControls(),
        ],
      ),
    );
  }

  Widget _gameCode() {
    return TintedCard(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      fillAlpha: 0.08,
      borderAlpha: 0.15,
      // FittedBox: the code is 24pt with 6pt letter-spacing, which overflows a
      // narrow phone (and any phone at a large text scale) without it.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Game Code: ',
              style: TextStyle(
                color: context.colors.onSurfaceMuted,
                fontSize: 16,
              ),
            ),
            Text(
              c.roomCode ?? '-----',
              style: TextStyle(
                color: context.colors.brand,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerTile(GamePlayer player) {
    final colors = context.colors;
    return TintedCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      tint: player.color,
      fillAlpha: 0.12,
      borderAlpha: 0.3,
      borderWidth: 1.5,
      child: Row(
        children: [
          PlayerAvatar(player: player, radius: 22, iconSize: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              player.id == c.myPlayerId ? '${player.name} (you)' : player.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (player.isHost)
            PillBadge(
              color: colors.brand,
              child: Text(
                'HOST',
                style: TextStyle(
                  color: colors.brand,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            )
          else if (player.hasPhotos)
            Icon(
              Icons.check_circle,
              semanticLabel: '${player.name} has added photos',
              color: colors.correct.withValues(alpha: 0.7),
            )
          else
            Icon(
              Icons.hourglass_empty,
              semanticLabel: '${player.name} has not added photos yet',
              color: colors.onSurfaceStrong.withValues(alpha: 0.35),
            ),
          // Only the host can kick, and never themselves — the server enforces
          // both, this just keeps the button from offering an impossible action.
          if (c.isHost && player.id != c.myPlayerId)
            IconButton(
              onPressed: () => _kick(player),
              tooltip: 'Remove ${player.name}',
              icon: Icon(
                Icons.person_remove,
                color: colors.onSurfaceFaint,
              ),
            ),
        ],
      ),
    );
  }

  /// Why START is disabled, so the host isn't left guessing.
  String _blockedReason() {
    if (c.players.length < 2) return 'NEED 2+ PLAYERS';
    return 'NEED PHOTOS FROM 2+ PLAYERS';
  }

  /// States the room's photo mode before anyone uploads.
  ///
  /// A player who does not notice they are in hardcore mode and shares
  /// something private is exactly the failure this must not cause, so the
  /// hardcore case is spelled out in full rather than hinted at, and the
  /// unknown case says so instead of implying a preview is coming.
  Widget _photoModeNotice() {
    final hardcore = c.hardcore;
    final colors = context.colors;
    final (IconData icon, Color color, String text) = switch (hardcore) {
      null => (
        Icons.hourglass_empty,
        // 54%, not the palette's 50% faint — kept exact.
        colors.onSurfaceStrong.withValues(alpha: 0.54),
        'Checking how photos are shared in this game…',
      ),
      true => (
        Icons.visibility_off,
        colors.brand,
        'HARDCORE — your photos are picked at random and shared '
            'without showing them to you first.',
      ),
      false => (
        Icons.visibility,
        colors.onSurfaceMuted,
        'You will see the picked photos and can reshuffle before sharing.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight:
                    hardcore == true ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Game settings. The host edits them; everyone else reads them, so nobody
  /// is surprised by how long the game is or how photos are shared.
  ///
  /// Hardcore is only editable while the room has no photos at all: after that
  /// the switch is disabled and says why. The server enforces the same lock,
  /// so this is convenience, not the guarantee.
  Widget _settingsPanel() {
    final colors = context.colors;
    final locked = c.anyPhotosUploaded;
    final hardcore = c.hardcore ?? false;
    return TintedCard(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      fillAlpha: 0.06,
      child: Column(
        children: [
          _settingRow(
            'Rounds',
            '${c.totalRounds}',
            onLess: c.totalRounds > 1
                ? () => _setSetting(totalRounds: c.totalRounds - 1)
                : null,
            onMore: c.totalRounds < 20
                ? () => _setSetting(totalRounds: c.totalRounds + 1)
                : null,
          ),
          _settingRow(
            'Seconds per round',
            '${c.roundSeconds}',
            onLess: c.roundSeconds > 5
                ? () => _setSetting(roundSeconds: c.roundSeconds - 5)
                : null,
            onMore: c.roundSeconds < 60
                ? () => _setSetting(roundSeconds: c.roundSeconds + 5)
                : null,
          ),
          if (c.isHost)
            SwitchListTile.adaptive(
              value: hardcore,
              onChanged:
                  locked ? null : (v) => _setSetting(hardcore: v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: colors.brand,
              title: Text(
                'Hardcore mode',
                style: TextStyle(
                  color: colors.onSurfaceStrong,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                locked
                    ? 'Locked — photos have already been added to this room.'
                    : "Everyone's photos are shared without a preview or "
                        'reshuffle. Locks once the first photo is added.',
                style: TextStyle(color: colors.onSurfaceMuted, fontSize: 12),
              ),
            )
          else
            _settingRow('Hardcore mode', hardcore ? 'ON' : 'OFF'),
        ],
      ),
    );
  }

  /// One setting line. Read-only unless a stepper callback is supplied, and
  /// only the host gets those.
  Widget _settingRow(
    String label,
    String value, {
    VoidCallback? onLess,
    VoidCallback? onMore,
  }) {
    final colors = context.colors;
    final stepper = c.isHost && (onLess != null || onMore != null);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: colors.onSurfaceStrong, fontSize: 15),
          ),
        ),
        if (stepper)
          IconButton(
            onPressed: onLess,
            tooltip: 'Fewer $label',
            icon: Icon(Icons.remove_circle_outline, color: colors.onSurfaceMuted),
          ),
        Text(
          value,
          style: TextStyle(
            color: colors.brand,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (stepper)
          IconButton(
            onPressed: onMore,
            tooltip: 'More $label',
            icon: Icon(Icons.add_circle_outline, color: colors.onSurfaceMuted),
          ),
      ],
    );
  }

  Widget _bottomControls() {
    // Everyone can add a photo; only the host can start, and only once at
    // least two people have contributed (the server enforces the same rule).
    final canStart = c.canStart;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          _photoModeNotice(),
          SecondaryButton(
            label: _uploading
                ? 'ADDING PHOTOS…'
                : _photoUploaded
                ? 'PHOTOS ADDED — ADD MORE'
                : 'ADD PHOTOS',
            icon: _photoUploaded ? Icons.check : Icons.add_a_photo,
            onPressed: _uploading || !c.photoModeKnown ? null : _addPhotos,
            height: 50,
            busy: _uploading,
            letterSpacing: null,
          ),
          const SizedBox(height: 12),
          if (c.isHost)
            PrimaryButton(
              label: canStart ? 'START GAME' : _blockedReason(),
              onPressed: canStart ? _start : null,
              height: 56,
              radius: 16,
              fontSize: 18,
            )
          else
            Text(
              'Waiting for the host to start…',
              style: TextStyle(color: colors.onSurfaceFaint, fontSize: 14),
            ),
        ],
      ),
    );
  }
}

/// Preview of the sampled photos with a reshuffle, so a player sees exactly
/// what they are about to share before it is uploaded.
class _PhotoPreviewSheet extends StatefulWidget {
  final PhotoSampler sampler;
  final List<SampledPhoto> initial;

  const _PhotoPreviewSheet({required this.sampler, required this.initial});

  @override
  State<_PhotoPreviewSheet> createState() => _PhotoPreviewSheetState();
}

class _PhotoPreviewSheetState extends State<_PhotoPreviewSheet> {
  late List<SampledPhoto> _photos = widget.initial;

  /// Everything already offered, so a reshuffle doesn't re-show the same
  /// pictures the player just rejected.
  late final Set<String> _seen = {for (final p in widget.initial) p.id};
  bool _reshuffling = false;

  Future<void> _reshuffle() async {
    setState(() => _reshuffling = true);
    try {
      final next = await widget.sampler.sampleRandomPhotos(
        count: photoSampleCount,
        exclude: _seen,
      );
      if (!mounted) return;
      if (next.isEmpty) {
        showSnack(context, 'No other photos to shuffle in');
        return;
      }
      setState(() {
        _photos = next;
        _seen.addAll(next.map((p) => p.id));
      });
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Reshuffle failed: $e');
    } finally {
      if (mounted) setState(() => _reshuffling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'THESE PHOTOS?',
              style: TextStyle(
                color: colors.onSurfaceStrong,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nothing is uploaded until you tap Use these',
              style: TextStyle(color: colors.onSurfaceFaint, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                itemCount: _photos.length,
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _photos[i].thumbnail,
                    fit: BoxFit.cover,
                    semanticLabel: 'Selected photo ${i + 1}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reshuffling ? null : _reshuffle,
                    icon: Icon(Icons.shuffle,
                        color: colors.onSurfaceStrong),
                    label: Text(
                      'RESHUFFLE',
                      style: TextStyle(color: colors.onSurfaceStrong),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _reshuffling
                        ? null
                        : () => Navigator.pop(context, _photos),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.brand,
                    ),
                    child: Text(
                      'USE THESE',
                      style: TextStyle(
                        color: colors.onSurfaceStrong,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
