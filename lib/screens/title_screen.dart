import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// The opening title screen, shown each time the app starts: the Scaffold
/// logo, the EventLens name with the healing heart, and the
/// "CORE MEMORY · 2010" banner (drawn in `tool/brand/brand.html`). It leaves
/// on its own after [duration], or straight away on a tap.
class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    required this.onDone,
    this.duration = defaultDuration,
  });

  static const defaultDuration = Duration(milliseconds: 1800);

  /// The brand kit's off-white, also the Android launch background, so the
  /// app opens on one colour.
  static const background = Color(0xFFFAFAF7);
  static const lockup = 'assets/brand/title_lockup.png';

  final VoidCallback onDone;
  final Duration duration;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Timer _timer;
  var _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _fade.value = 1;
    } else if (!_fade.isAnimating && _fade.value == 0) {
      _fade.forward();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _timer.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = min(MediaQuery.sizeOf(context).width * 0.78, 340.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: ColoredBox(
        color: TitleScreen.background,
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              // Screen readers get the title while it fades in.
              alwaysIncludeSemantics: true,
              child: Image.asset(
                TitleScreen.lockup,
                width: width,
                semanticLabel: 'EventLens, by Scaffold. Core memory, 2010.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
