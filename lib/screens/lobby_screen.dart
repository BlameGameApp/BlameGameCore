import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/game_models.dart';
import '../services/photo_sampler.dart';
import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_buttons.dart';
import '../ui/connection_banner.dart';
import '../ui/controller_screen.dart';
import '../ui/error_text.dart';
import '../ui/player_cosmetics.dart';
import '../ui/player_token.dart';
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
  bool _uploading = false;
  bool _copied = false;
  Timer? _copiedReset;

  int get _myPhotos => c.me?.photoCount ?? 0;

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
          builder: (_) => _PhotoPreviewSheet(sampler: _sampler, initial: photos),
        );
        if (chosen == null || chosen.isEmpty) return;
        confirmed = chosen;
      }
      // No confirmation message: the player's row counts them as they land,
      // and a snackbar would sit on top of the button they want next.
      await c.uploadPhotos([for (final p in confirmed) p.bytes]);
    } on PhotoPermissionDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Allow photo access to add photos'),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: _sampler.openSettings,
          ),
        ),
      );
    } catch (e) {
      snack('Upload failed: ${friendlyError(e)}');
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

  /// Leave the room. Asked first because it takes the player's photos with
  /// it. After that we pop regardless: the player asked to go, so a failed
  /// call shouldn't trap them in a lobby they've mentally left.
  Future<void> _leave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave this game?'),
        content: Text(
          c.players.length > 1 && c.isHost
              ? 'Your photos will be removed and the next player becomes host.'
              : 'Your photos will be removed.',
        ),
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
    if (leave != true) return;
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

  /// Confirmed on the code itself rather than with a snackbar, which would
  /// cover the main button for as long as it's up.
  Future<void> _copyCode() async {
    final code = c.roomCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  /// Opened on demand: the defaults are fine for most games, and the lobby has
  /// one job, which is getting everyone in with their photos.
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListenableBuilder(
        listenable: c,
        builder: (context, _) => _SettingsSheet(
          controller: c,
          onChange: _setSetting,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          // IconButton, not a bare GestureDetector: a 24x24 icon is half the
          // 48x48 minimum tap target and carries no button semantics for
          // screen readers.
          leading: IconButton(
            onPressed: _leave,
            tooltip: 'Leave room',
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Lobby'),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConnectionBanner(controller: c),
              Expanded(
                child: ListView(
                  children: [
                    _gameCode(),
                    _settingsSummary(),
                    _playersHeader(),
                    for (final player in c.players)
                      KeyedSubtree(
                        key: ValueKey(player.id),
                        child: _playerRow(player),
                      ),
                    if (c.players.length < 2)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          'Round up some suspects: give them the code above.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                  ],
                ),
              ),
              // Pinned, however long the list gets: the mode has to be in view
              // whenever the button that shares photos is.
              const SizedBox(height: 8),
              _photoModeNotice(),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  /// The code gets read aloud across a room, so it's the largest thing here,
  /// and spaced so the characters don't run together. Tapping it copies it,
  /// for sending to someone who isn't in the room.
  Widget _gameCode() {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _copyCode,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Game code', style: text.bodyMedium),
                      Text(
                        c.roomCode ?? '-----',
                        style: text.displaySmall!.copyWith(
                          color: colors.ink,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_copied)
                  Text('Copied', style: text.titleMedium)
                else
                  Icon(
                    Icons.copy,
                    color: colors.muted,
                    semanticLabel: 'Copy game code',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Says how close the room is to being able to start, which is the only
  /// thing anyone is waiting for here.
  Widget _playersHeader() {
    final text = Theme.of(context).textTheme;
    final ready = c.players.where((p) => p.hasPhotos).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Players (${c.players.length})', style: text.titleMedium),
          Text('$ready of ${c.players.length} ready', style: text.bodyMedium),
        ],
      ),
    );
  }

  Widget _playerRow(GamePlayer player) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final isMe = player.id == c.myPlayerId;
    final photos = switch (player.photoCount) {
      0 => 'no photos yet',
      1 => '1 photo',
      final n => '$n photos',
    };
    return ListTile(
      leading: PlayerToken(
        name: player.name,
        piece: c.players.pieceOf(player.id),
        popIn: true,
      ),
      title: Text(
        isMe ? '${player.name} (you)' : player.name,
        style: text.titleMedium,
      ),
      subtitle: Text(
        player.isHost
            ? 'Host, $photos'
            : '${photos[0].toUpperCase()}${photos.substring(1)}',
      ),
      // Only the host can kick, and never themselves — the server enforces
      // both, this just keeps the button from offering an impossible action.
      trailing: c.isHost && !isMe
          ? IconButton(
              onPressed: () => _kick(player),
              tooltip: 'Remove ${player.name}',
              icon: Icon(Icons.close, color: colors.muted),
            )
          : null,
    );
  }

  String get _gameLength {
    final rounds = c.totalRounds == 1 ? '1 round' : '${c.totalRounds} rounds';
    return '$rounds, ${c.roundSeconds} seconds each';
  }

  /// Everyone sees what the game will be. Only the host gets to change it.
  Widget _settingsSummary() {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _gameLength,
                style: text.bodyMedium,
              ),
            ),
            if (c.isHost)
              TextButton(
                onPressed: _openSettings,
                child: const Text('Change'),
              ),
          ],
        ),
      ),
    );
  }

  /// States the room's photo mode before anyone uploads.
  ///
  /// A player who does not notice they are in hardcore mode and shares
  /// something private is exactly the failure this must not cause, so the
  /// hardcore case is spelled out in full in the alert colour, and the unknown
  /// case says so instead of implying a preview is coming.
  Widget _photoModeNotice() {
    final hardcore = c.hardcore;
    final colors = context.colors;
    final text = switch (hardcore) {
      null => 'Checking how photos are shared in this game…',
      true =>
        'Hardcore mode: your photos are picked at random and shared '
            'without showing them to you first.',
      false => 'You will see the picked photos and can reshuffle before sharing.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: hardcore == true ? colors.alert : null,
          fontWeight: hardcore == true ? FontWeight.w600 : null,
        ),
      ),
    );
  }

  /// What's stopping the host, in terms of who has to do what.
  String _blockedReason() {
    if (c.players.length < 2) return 'Waiting for players to join';
    return 'Waiting for another player to add photos';
  }

  /// There is one main button, and it's always the next thing this player
  /// should do: add photos until they have, then start, or wait for whoever
  /// can. Anything else they could do stays available as a second button.
  /// (Only the host can start, and only once at least two people have
  /// contributed; the server enforces the same rule.)
  Widget _actions() {
    final text = Theme.of(context).textTheme;
    final canAdd = _myPhotos < maxPhotosPerPlayer;
    final onAdd = _uploading || !c.photoModeKnown ? null : _addPhotos;
    final needPhotos = _myPhotos == 0;

    final Widget primary;
    if (c.isHost && c.canStart) {
      primary = PrimaryButton(label: 'Start game', onPressed: _start);
    } else if (needPhotos) {
      primary = PrimaryButton(
        label: 'Add photos',
        onPressed: onAdd,
        busy: _uploading,
      );
    } else if (c.isHost) {
      primary = PrimaryButton(label: _blockedReason(), onPressed: null);
    } else {
      primary = PrimaryButton(
        label: 'Waiting for the host to start',
        onPressed: null,
      );
    }
    // Adding photos is the main button in that case, so it isn't offered twice.
    final addIsPrimary = needPhotos && !(c.isHost && c.canStart);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (!addIsPrimary) ...[
            const SizedBox(height: 8),
            // Stays at the limit, disabled: the button above it is what the
            // player taps next, and it shouldn't move out from under their
            // thumb. This way the limit gets explained as well.
            SecondaryButton(
              label: !canAdd
                  ? 'Photo limit reached'
                  : needPhotos
                  ? 'Add photos'
                  : 'Add more photos',
              onPressed: canAdd ? onAdd : null,
              busy: _uploading,
            ),
          ],
          if (!c.isHost && needPhotos) ...[
            const SizedBox(height: 8),
            Text(
              'The host starts the game once photos are in',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// How the game is set up. The server answers each change with a
/// `settings_updated` broadcast, and that's what moves these values, so this
/// only ever shows what's really been accepted.
///
/// Hardcore is only editable while the room has no photos at all: after that
/// the switch is disabled and says why. The server enforces the same lock, so
/// this is convenience, not the guarantee.
class _SettingsSheet extends StatelessWidget {
  final GameController controller;
  final Future<void> Function({
    int? totalRounds,
    int? roundSeconds,
    bool? hardcore,
  })
  onChange;

  const _SettingsSheet({required this.controller, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final locked = c.anyPhotosUploaded;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Game settings', style: text.headlineSmall),
            const SizedBox(height: 8),
            _stepper(
              context,
              'Rounds',
              c.totalRounds,
              onLess: c.totalRounds > 1
                  ? () => onChange(totalRounds: c.totalRounds - 1)
                  : null,
              onMore: c.totalRounds < 20
                  ? () => onChange(totalRounds: c.totalRounds + 1)
                  : null,
            ),
            _stepper(
              context,
              'Seconds per round',
              c.roundSeconds,
              onLess: c.roundSeconds > 5
                  ? () => onChange(roundSeconds: c.roundSeconds - 5)
                  : null,
              onMore: c.roundSeconds < 60
                  ? () => onChange(roundSeconds: c.roundSeconds + 5)
                  : null,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: c.hardcore ?? false,
              onChanged: locked ? null : (v) => onChange(hardcore: v),
              title: Text('Hardcore mode', style: text.titleMedium),
              // Styled explicitly: a disabled tile fades its subtitle, and this
              // is the line that says why it's disabled.
              subtitle: Text(
                locked
                    ? 'Locked: photos have been added'
                    : 'Photos are shared without a preview or reshuffle',
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The tooltips name the setting: two identical minus signs are otherwise
  /// indistinguishable to a screen reader.
  Widget _stepper(
    BuildContext context,
    String label,
    int value, {
    required VoidCallback? onLess,
    required VoidCallback? onMore,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.titleMedium)),
          IconButton.filledTonal(
            onPressed: onLess,
            tooltip: 'Fewer $label',
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
          ),
          IconButton.filledTonal(
            onPressed: onMore,
            tooltip: 'More $label',
            icon: const Icon(Icons.add),
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
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share these photos?', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Picked at random. Nothing is shared until you tap Use these.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: _photos.length,
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _photos[i].thumbnail,
                    fit: BoxFit.cover,
                    semanticLabel: 'Selected photo ${i + 1}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Use these',
              onPressed: _reshuffling
                  ? null
                  : () => Navigator.pop(context, _photos),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Reshuffle',
              onPressed: _reshuffling ? null : _reshuffle,
              busy: _reshuffling,
            ),
          ],
        ),
      ),
    );
  }
}
