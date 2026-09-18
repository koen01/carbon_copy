import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _Step {
  final IconData icon;
  final String title;
  final String body;
  const _Step(this.icon, this.title, this.body);
}

const _steps = [
  _Step(
    Icons.print,
    'Welcome to Carbon Copy',
    'Your Elegoo Centauri Carbon 2\'s live camera feed and print status — always at a glance.',
  ),
  _Step(
    Icons.videocam,
    'Live Camera Feed',
    'Your printer\'s feed fills the screen in real time. Pinch to zoom up to 6×, or double-tap to reset.',
  ),
  _Step(
    Icons.layers,
    'Print Status Overlay',
    'Tap anywhere to show or hide the overlay. It displays temperatures, progress, layer count, and ETA.',
  ),
  _Step(
    Icons.settings,
    'Settings & More',
    'Tap the gear icon to configure your printer, enable split-screen for a second printer, or toggle the debug log.',
  ),
];

class WalkthroughOverlay extends StatefulWidget {
  final VoidCallback onDone;

  const WalkthroughOverlay({super.key, required this.onDone});

  @override
  State<WalkthroughOverlay> createState() => _WalkthroughOverlayState();
}

class _WalkthroughOverlayState extends State<WalkthroughOverlay> {
  int _step = 0;
  final _skipFocus = FocusNode();
  final _nextFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    _skipFocus.onKeyEvent = (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowRight) {
        _nextFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA) {
        widget.onDone();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    _nextFocus.onKeyEvent = (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft) {
        _skipFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.space) {
        _next();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nextFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _skipFocus.dispose();
    _nextFocus.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      widget.onDone();
    }
  }

  KeyEventResult _handleBackKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onDone();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;

    return Focus(
      onKeyEvent: _handleBackKey,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(step.icon, size: 64, color: Colors.white),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: Text(
                  step.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _step ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _step ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _WalkthroughButton(
                    focusNode: _skipFocus,
                    onPressed: widget.onDone,
                    label: 'Skip',
                    isPrimary: false,
                  ),
                  const SizedBox(width: 24),
                  _WalkthroughButton(
                    focusNode: _nextFocus,
                    onPressed: _next,
                    label: isLast ? 'Get started' : 'Next',
                    isPrimary: true,
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalkthroughButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final String label;
  final bool isPrimary;

  const _WalkthroughButton({
    required this.focusNode,
    required this.onPressed,
    required this.label,
    required this.isPrimary,
  });

  @override
  State<_WalkthroughButton> createState() => _WalkthroughButtonState();
}

class _WalkthroughButtonState extends State<_WalkthroughButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPrimary) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _focused ? Colors.white : Colors.transparent,
            width: 3,
          ),
        ),
        child: ElevatedButton(
          focusNode: widget.focusNode,
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: Text(widget.label, style: const TextStyle(fontSize: 15)),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focused ? Colors.white54 : Colors.transparent,
          width: 2,
        ),
      ),
      child: TextButton(
        focusNode: widget.focusNode,
        onPressed: widget.onPressed,
        child: Text(
          widget.label,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ),
    );
  }
}
