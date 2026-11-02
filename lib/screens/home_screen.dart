import 'package:flutter/material.dart';

import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/band.dart';
import '../ui/error_text.dart';
import '../ui/fit_text.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() => _run((c) => c.createAndHost(_name));

  Future<void> _joinRoom() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a game code to join');
      return Future.value();
    }
    return _run((c) => c.joinByCode(code, _name));
  }

  String get _name {
    final n = _nameController.text.trim();
    return n.isEmpty ? 'Player' : n;
  }

  /// Runs an async action that sets up a GameController, then navigates to the
  /// lobby. Shows a spinner and surfaces errors.
  Future<void> _run(Future<void> Function(GameController) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = GameController();
    try {
      await action(controller);
      if (!mounted) {
        controller.dispose();
        return;
      }
      // Home created it, so Home tears it down: awaiting the push means this
      // runs whenever the game flow unwinds back here, however it unwinds.
      // Without it every game leaks a live WebSocket and an http.Client.
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LobbyScreen(controller: controller)),
      );
      controller.dispose();
    } catch (e) {
      controller.dispose();
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    return PosterScaffold(
      top: colors.marigold,
      background: colors.paper,
      resizeForKeyboard: true,
      body: Column(
        children: [
          // The title takes whatever the form and the keyboard leave, which is
          // what keeps the fields on screen without a scroll view: the two
          // lines simply get shorter when the keyboard comes up.
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Band(
                    color: colors.marigold,
                    padding: EdgeInsets.fromLTRB(
                      bandGutter,
                      top + 4,
                      bandGutter,
                      14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guess whose photo it is',
                          style: uiText(16, weight: 700, color: colors.ink),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: FitText(
                            'PHOTO',
                            color: colors.ink,
                            semanticsLabel: 'Photo Blame',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Band(
                    color: colors.vermilion,
                    padding: const EdgeInsets.fromLTRB(
                      bandGutter,
                      14,
                      bandGutter,
                      14,
                    ),
                    child: ExcludeSemantics(
                      child: FitText('BLAME', color: colors.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Band(
              color: colors.ink,
              padding: const EdgeInsets.symmetric(
                horizontal: bandGutter,
                vertical: 12,
              ),
              child: Text(
                _error!,
                style: uiText(15, weight: 600, color: colors.paper),
              ),
            ),
          _textField(
            _nameController,
            'Your name',
            capitalization: TextCapitalization.words,
          ),
          BandButton(
            label: _busy ? 'Starting…' : 'Start a game',
            onPressed: _busy ? null : _createRoom,
            color: colors.ink,
            textColor: colors.paper,
            busy: _busy,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _textField(
                  _codeController,
                  'Game code',
                  capitalization: TextCapitalization.characters,
                  last: true,
                ),
              ),
              SizedBox(
                width: 112,
                child: BandButton(
                  label: 'Join',
                  onPressed: _busy ? null : _joinRoom,
                  color: colors.cobalt,
                  textColor: colors.paper,
                  last: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    required TextCapitalization capitalization,
    bool last = false,
  }) {
    final colors = context.colors;
    final inset = last ? MediaQuery.paddingOf(context).bottom : 0.0;
    return Band(
      color: colors.paper,
      height: 68 + inset,
      padding: EdgeInsets.fromLTRB(bandGutter, 0, bandGutter, inset),
      child: Center(
        child: TextField(
          controller: controller,
          textCapitalization: capitalization,
          style: uiText(21, weight: 700, color: colors.ink),
          decoration: InputDecoration.collapsed(
            hintText: hint,
            hintStyle: uiText(21, weight: 700, color: colors.inkMuted),
          ),
        ),
      ),
    );
  }
}
