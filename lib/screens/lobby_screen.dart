import 'package:flutter/material.dart';

import '../config.dart';
import '../models/game_models.dart';
import '../services/photo_sampler.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/band.dart';
import '../ui/connection_banner.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/fit_text.dart';
import '../ui/player_cosmetics.dart';
import '../ui/snack.dart';
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
    // Kicked out: leave the lobby instead of sitting in a room we're not in.
    if (c.hasLeftRoom) {
      return navigateOnce(() {
        final reason = c.removedFromRoom;
        // Grab the messenger before popping: showing the snackbar on this
        // route and then popping takes the explanation down with the lobby,
        // so the kicked player is ejected with no idea why.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        if (reason != null) {
          messenger.showSnackBar(SnackBar(content: Text(reason)));
        }
      });
    }
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
          useSafeArea: true,
          backgroundColor: context.colors.ink,
          shape: const RoundedRectangleBorder(),
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
    return PosterScaffold(
      top: colors.ink,
      body: Column(
        children: [
          _codeBand(),
          ConnectionBanner(controller: c),
          Expanded(child: _lineUp()),
          _settings(),
          _photoModeNotice(),
          _actions(),
        ],
      ),
    );
  }

  /// The code is the first thing anyone needs and it gets read aloud across a
  /// room, so it is the biggest thing on the screen.
  Widget _codeBand() {
    final colors = context.colors;
    return Band(
      color: colors.ink,
      padding: EdgeInsets.fromLTRB(
        4,
        MediaQuery.paddingOf(context).top,
        bandGutter,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // IconButton, not a bare GestureDetector: a 24x24 icon is
              // half the 48x48 minimum tap target and carries no button
              // semantics for screen readers.
              IconButton(
                onPressed: _leave,
                tooltip: 'Leave room',
                icon: Icon(Icons.arrow_back_sharp, color: colors.paper),
              ),
              Text(
                'Game code',
                style: uiText(16, weight: 700, color: colors.paper),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: bandGutter - 4, top: 4),
            child: SizedBox(
              height: 76,
              child: FitText(c.roomCode ?? '-----', color: colors.paper),
            ),
          ),
        ],
      ),
    );
  }

  /// The players, stacked. The bands share out all the height there is, so the
  /// poster is always full: a room of one is one enormous name, and each
  /// arrival splits it. It only scrolls once there's more than fits at
  /// [_minBand], which at 12 players on a small phone there will be.
  static const double _minBand = 76;

  Widget _lineUp() {
    return LayoutBuilder(
      builder: (context, box) {
        final count = c.players.length;
        final share = count == 0 ? box.maxHeight : box.maxHeight / count;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: share < _minBand ? _minBand : share),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, height, _) => ListView.builder(
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemExtent: height,
            itemCount: count,
            itemBuilder: (context, i) => _playerBand(c.players[i]),
          ),
        );
      },
    );
  }

  Widget _playerBand(GamePlayer player) {
    final isMe = player.id == c.myPlayerId;
    // Only the host can remove someone, and never themselves — the server
    // enforces both, this just keeps the band from offering an impossible
    // action. The whole band is the target: there's no room on it for a
    // 48x48 button that wouldn't cut into the name.
    final removable = c.isHost && !isMe;
    final role = isMe && player.isHost
        ? 'You, hosting'
        : isMe
        ? 'You'
        : player.isHost
        ? 'Host'
        : null;
    final photos = switch (player.photoCount) {
      0 => 'No photos yet',
      1 => '1 photo',
      final n => '$n photos',
    };
    final band = PlayerBand(
      name: player.name,
      ink: c.players.inkOf(player.id),
      leading: role,
      trailing: photos,
      actionLabel: removable ? 'Remove ${player.name}, $photos' : null,
      onTap: removable ? () => _kick(player) : null,
    );
    if (!removable) return band;
    return Tooltip(
      message: 'Remove ${player.name}',
      excludeFromSemantics: true,
      child: band,
    );
  }

  /// Why Start is disabled, so the host isn't left guessing.
  String _blockedReason() {
    if (c.players.length < 2) return 'Need 2+ players';
    return 'Need photos from 2+ players';
  }

  /// States the room's photo mode before anyone uploads.
  ///
  /// A player who does not notice they are in hardcore mode and shares
  /// something private is exactly the failure this must not cause, so the
  /// hardcore case takes a band of its own in the alarm colour and is spelled
  /// out in full, and the unknown case says so instead of implying a preview
  /// is coming.
  Widget _photoModeNotice() {
    final hardcore = c.hardcore;
    final colors = context.colors;
    final (Color fill, Color ink, String text) = switch (hardcore) {
      null => (
        colors.paper,
        colors.inkMuted,
        'Checking how photos are shared in this game…',
      ),
      true => (
        colors.vermilion,
        colors.ink,
        'Hardcore: your photos are picked at random and shared '
            'without showing them to you first.',
      ),
      false => (
        colors.paper,
        colors.inkMuted,
        'You will see the picked photos and can reshuffle before sharing.',
      ),
    };
    return Band(
      color: fill,
      padding: const EdgeInsets.fromLTRB(bandGutter, 10, bandGutter, 14),
      child: Text(
        text,
        style: uiText(14, weight: hardcore == true ? 700 : 500, color: ink),
      ),
    );
  }

  /// Game settings. The host edits them; everyone else reads them, so nobody
  /// is surprised by how long the game is or how photos are shared.
  ///
  /// Hardcore is only editable while the room has no photos at all: after that
  /// the switch is disabled and says why. The server enforces the same lock,
  /// so this is convenience, not the guarantee.
  Widget _settings() {
    final colors = context.colors;
    final label = uiText(16, weight: 700, color: colors.ink);
    if (!c.isHost) {
      return Band(
        color: colors.paper,
        padding: const EdgeInsets.fromLTRB(bandGutter, 12, bandGutter, 8),
        // Not the photo mode: the band below this one states that in full.
        child: Text(
          '${c.totalRounds} rounds, ${c.roundSeconds} seconds each',
          style: label,
        ),
      );
    }
    final locked = c.anyPhotosUploaded;
    final hardcore = c.hardcore ?? false;
    return Band(
      color: colors.paper,
      padding: const EdgeInsets.fromLTRB(bandGutter, 10, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _stepper(
                  'Rounds',
                  c.totalRounds,
                  onLess: c.totalRounds > 1
                      ? () => _setSetting(totalRounds: c.totalRounds - 1)
                      : null,
                  onMore: c.totalRounds < 20
                      ? () => _setSetting(totalRounds: c.totalRounds + 1)
                      : null,
                ),
              ),
              Expanded(
                child: _stepper(
                  'Seconds',
                  c.roundSeconds,
                  onLess: c.roundSeconds > 5
                      ? () => _setSetting(roundSeconds: c.roundSeconds - 5)
                      : null,
                  onMore: c.roundSeconds < 60
                      ? () => _setSetting(roundSeconds: c.roundSeconds + 5)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hardcore mode', style: label),
                    Text(
                      locked
                          ? 'Locked: photos have been added'
                          : 'No preview, no reshuffle',
                      style: uiText(13, color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: hardcore,
                onChanged: locked ? null : (v) => _setSetting(hardcore: v),
                activeTrackColor: colors.vermilion,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A value with its two buttons either side, so the pair reads as one
  /// control. Their tooltips name the setting: two identical minus signs are
  /// otherwise indistinguishable to a screen reader.
  Widget _stepper(
    String label,
    int value, {
    required VoidCallback? onLess,
    required VoidCallback? onMore,
  }) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: uiText(22, weight: 900, color: colors.ink)),
              Text(label, style: uiText(13, color: colors.inkMuted)),
            ],
          ),
        ),
        IconButton(
          onPressed: onLess,
          tooltip: 'Fewer $label',
          icon: const Icon(Icons.remove_sharp),
        ),
        IconButton(
          onPressed: onMore,
          tooltip: 'More $label',
          icon: const Icon(Icons.add_sharp),
        ),
      ],
    );
  }

  Widget _actions() {
    // Everyone can add a photo; only the host can start, and only once at
    // least two people have contributed (the server enforces the same rule).
    final canStart = c.canStart;
    final colors = context.colors;
    return Column(
      children: [
        BandButton(
          label: _uploading
              ? 'Adding photos…'
              : _photoUploaded
              ? 'Add more photos'
              : 'Add photos',
          onPressed: _uploading || !c.photoModeKnown ? null : _addPhotos,
          color: colors.cobalt,
          textColor: colors.paper,
          busy: _uploading,
          height: 60,
        ),
        if (c.isHost)
          BandButton(
            label: canStart ? 'Start game' : _blockedReason(),
            onPressed: canStart ? _start : null,
            color: colors.vermilion,
            textColor: colors.ink,
            last: true,
          )
        else
          Band(
            color: colors.ink,
            height: 68 + MediaQuery.paddingOf(context).bottom,
            padding: EdgeInsets.fromLTRB(
              bandGutter,
              0,
              bandGutter,
              MediaQuery.paddingOf(context).bottom,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Waiting for the host to start…',
                style: uiText(16, weight: 700, color: colors.paperMuted),
              ),
            ),
          ),
      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(bandGutter, 20, bandGutter, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These photos?',
                style: uiText(28, weight: 900, color: colors.paper),
              ),
              const SizedBox(height: 4),
              Text(
                'Nothing is uploaded until you tap Use these',
                style: uiText(15, color: colors.paperMuted),
              ),
            ],
          ),
        ),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, i) => Image.memory(
              _photos[i].thumbnail,
              fit: BoxFit.cover,
              semanticLabel: 'Selected photo ${i + 1}',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: BandButton(
                label: 'Reshuffle',
                onPressed: _reshuffling ? null : _reshuffle,
                color: colors.paper,
                textColor: colors.ink,
                busy: _reshuffling,
                last: true,
              ),
            ),
            Expanded(
              child: BandButton(
                label: 'Use these',
                onPressed: _reshuffling
                    ? null
                    : () => Navigator.pop(context, _photos),
                color: colors.vermilion,
                textColor: colors.ink,
                last: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
