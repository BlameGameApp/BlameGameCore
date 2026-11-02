import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/game_controller.dart';
import '../theme/app_theme.dart';
import '../ui/app_buttons.dart';
import '../ui/error_text.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameFocus = FocusNode();
  final _codeFocus = FocusNode();
  bool _joining = false;
  bool _starting = false;
  String? _nameError;
  String? _codeError;
  String? _error;

  bool get _busy => _joining || _starting;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _nameFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Everyone in a round is told apart by name, so one is required up front
  /// rather than quietly filled in: two silent "Player"s can't share a room.
  bool _checkName() {
    if (_nameController.text.trim().isNotEmpty) return true;
    setState(() => _nameError = 'Enter your name');
    _nameFocus.requestFocus();
    return false;
  }

  Future<void> _startGame() async {
    setState(() => _codeError = null);
    if (!_checkName()) return;
    setState(() => _starting = true);
    await _run((c) => c.createAndHost(_nameController.text.trim()));
  }

  Future<void> _joinGame() async {
    if (!_checkName()) return;
    final code = _codeController.text.trim();
    if (code.length != 5) {
      setState(() => _codeError = 'Enter the 5-character code');
      _codeFocus.requestFocus();
      return;
    }
    setState(() => _joining = true);
    await _run((c) => c.joinByCode(code, _nameController.text.trim()));
  }

  /// Runs an async action that sets up a GameController, then navigates to the
  /// lobby. Shows a spinner and surfaces errors.
  Future<void> _run(Future<void> Function(GameController) action) async {
    setState(() {
      _nameError = null;
      _codeError = null;
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
      // That game is over, so its code is no use to the next one.
      _codeController.clear();
    } catch (e) {
      controller.dispose();
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _joining = false;
          _starting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The header takes whatever height the form leaves, down to its own
      // size. Past that the page scrolls, so the form can't be pushed under the
      // keyboard on a small phone or at a large text size.
      body: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _header()),
                  _form(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return ColoredBox(
      color: colors.brand,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Photo Blame',
                style: text.displaySmall!.copyWith(color: colors.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'Guess whose photo it is',
                style: text.bodyLarge!.copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(24)],
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              decoration: InputDecoration(
                labelText: 'Your name',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              focusNode: _codeFocus,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.go,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                TextInputFormatter.withFunction(
                  (_, next) => next.copyWith(text: next.text.toUpperCase()),
                ),
                LengthLimitingTextInputFormatter(5),
              ],
              onChanged: (_) {
                if (_codeError != null) setState(() => _codeError = null);
              },
              onSubmitted: (_) => _joinGame(),
              decoration: InputDecoration(
                labelText: 'Game code',
                errorText: _codeError,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colors.alert)),
            ],
            const SizedBox(height: 16),
            // Joining comes first because it's what nearly everyone does: one
            // person in a room starts the game and the rest type its code.
            PrimaryButton(
              label: 'Join game',
              onPressed: _starting ? null : _joinGame,
              busy: _joining,
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Start a new game',
              onPressed: _joining ? null : _startGame,
              busy: _starting,
            ),
          ],
        ),
      ),
    );
  }
}
