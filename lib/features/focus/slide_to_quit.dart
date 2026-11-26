import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A horizontal slide-to-confirm control for ending a focus session.
///
/// The result is decided by the release position, never by fling velocity: a
/// thumb released past [threshold] confirms, and anything earlier snaps back.
/// The whole track accepts the drag so the gesture is forgiving, and it exposes
/// a button semantics node plus Enter/Space activation for assistive input.
/// Implicit motion collapses to zero when the platform requests reduced motion;
/// the distance release and direct drag stay the same.
class SlideToQuit extends StatefulWidget {
  const SlideToQuit({
    required this.onQuit,
    this.enabled = true,
    this.label = 'Slide to quit focus',
    this.disabledLabel = 'Finish saving first',
    this.trackColor,
    this.thumbColor,
    this.onThumbColor,
    this.labelColor,
    this.focusColor,
    super.key,
  });

  /// Runs the confirmation flow. Returns true when the session actually ended,
  /// so the control can keep the thumb over while the host replaces the page.
  final Future<bool> Function() onQuit;

  final bool enabled;
  final String label;
  final String disabledLabel;
  final Color? trackColor;
  final Color? thumbColor;
  final Color? onThumbColor;
  final Color? labelColor;
  final Color? focusColor;

  /// Fraction of travel that confirms on release. Explicit distance, not
  /// velocity, so a fast flick that stops short cannot quit by accident.
  static const threshold = 0.72;

  static const trackKey = Key('slide-to-quit-track');
  static const thumbKey = Key('slide-to-quit-thumb');
  static const semanticsKey = Key('slide-to-quit-semantics');

  @override
  State<SlideToQuit> createState() => _SlideToQuitState();
}

class _SlideToQuitState extends State<SlideToQuit> {
  static const _thumbSize = 52.0;
  static const _inset = 6.0;

  double _progress = 0;
  bool _dragging = false;
  bool _busy = false;
  bool _showFocus = false;

  bool get _enabled => widget.enabled && !_busy;

  @override
  void didUpdateWidget(covariant SlideToQuit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _dragging = false;
      _progress = 0;
    }
  }

  Future<void> _requestQuit() async {
    if (!_enabled) return;
    setState(() => _busy = true);
    var confirmed = false;
    try {
      confirmed = await widget.onQuit();
    } catch (_) {
      // A failed confirmation leaves the session intact; snap the thumb back.
      confirmed = false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (!confirmed) _progress = 0;
        });
      }
    }
  }

  void _onDragStart(DragStartDetails _) {
    if (!_enabled) return;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details, double travel) {
    if (!_enabled || !_dragging) return;
    setState(() {
      _progress = (_progress + details.delta.dx / travel).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_enabled) return;
    final reached = _progress >= SlideToQuit.threshold;
    setState(() => _dragging = false);
    if (reached) {
      unawaited(_requestQuit());
    } else {
      setState(() => _progress = 0);
    }
  }

  void _onDragCancel() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _progress = 0;
    });
  }

  String get _label {
    if (_busy) return 'Confirm to quit';
    if (!widget.enabled) return widget.disabledLabel;
    if (_dragging && _progress >= SlideToQuit.threshold) return 'Release to quit';
    if (_dragging || _progress > 0) return 'Keep sliding';
    return widget.label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final trackColor = widget.trackColor ?? scheme.surfaceContainerHighest;
    final thumbColor = widget.thumbColor ?? scheme.onSurface;
    final onThumbColor = widget.onThumbColor ?? scheme.surface;
    final labelColor = widget.labelColor ?? scheme.onSurfaceVariant;
    final focusColor = widget.focusColor ?? thumbColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = math.max(
          1.0,
          constraints.maxWidth - _inset * 2 - _thumbSize,
        );
        final left = _inset + _progress * travel;

        return FocusableActionDetector(
          enabled: _enabled,
          onShowFocusHighlight: (value) => setState(() => _showFocus = value),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                unawaited(_requestQuit());
                return null;
              },
            ),
          },
          child: Semantics(
            key: SlideToQuit.semanticsKey,
            container: true,
            button: true,
            enabled: _enabled,
            label: widget.label,
            hint: _enabled
                ? 'Slide the handle to the end, or double tap to quit.'
                : widget.disabledLabel,
            onTap: _enabled ? () => unawaited(_requestQuit()) : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _enabled ? _onDragStart : null,
              onHorizontalDragUpdate: _enabled
                  ? (details) => _onDragUpdate(details, travel)
                  : null,
              onHorizontalDragEnd: _enabled
                  ? (details) => _onDragEnd(details)
                  : null,
              onHorizontalDragCancel: _enabled ? _onDragCancel : null,
              child: AnimatedContainer(
                key: SlideToQuit.trackKey,
                height: 64,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: _showFocus ? focusColor : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: ExcludeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 68),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _label,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: labelColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: _dragging || reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      left: left,
                      top: _inset,
                      width: _thumbSize,
                      height: _thumbSize,
                      child: Container(
                        key: SlideToQuit.thumbKey,
                        decoration: BoxDecoration(
                          color: thumbColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: onThumbColor,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
