import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../design/appearance_preferences.dart';
import 'card_effect_painter.dart';

/// Draws the card's surface for [style] in the app's neutral roles.
///
/// Filled is a quiet container, outlined a plain surface with a strong edge,
/// and glass a wash with a light sheen. Shared with the settings swatches so a
/// choice there matches the real card.
BoxDecoration focusCardDecoration(
  FocusCardStyle style,
  ColorScheme scheme,
  BorderRadius borderRadius,
) => switch (style) {
  FocusCardStyle.filled => BoxDecoration(
    color: scheme.surfaceContainer,
    borderRadius: borderRadius,
    border: Border.all(color: scheme.outlineVariant),
  ),
  FocusCardStyle.outlined => BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: borderRadius,
    border: Border.all(color: scheme.outline, width: 1.5),
  ),
  FocusCardStyle.glass => BoxDecoration(
    color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
    borderRadius: borderRadius,
    border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
  ),
};

/// The light falling across the top-left of a glass card.
LinearGradient focusCardSheenGradient(bool dark) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[
    Colors.white.withValues(alpha: dark ? 0.08 : 0.35),
    Colors.white.withValues(alpha: 0),
  ],
  stops: const <double>[0, 0.55],
);

/// Presents timer content on a card with an optional moving effect behind it.
///
/// The effect follows [progress] and only advances while [running] and motion
/// is allowed, so pausing freezes the exact frame: wind, drops and embers stay
/// where the clock stopped instead of disappearing. A still frame is a
/// different state, used when reduce-motion is on or under [lowPower]; it draws
/// the effect's rest composition without the moving particles.
///
/// [reducedMotion] adds to the platform reduce-motion preference and can never
/// turn that preference back off. [animates] lets a host stop the clock while
/// the card is offscreen, and [TickerMode] stops it for an inactive tab or a
/// route that was pushed over.
///
/// The widget owns no timer state. Pass the current values from the timer and
/// leave pausing, planning and persistence to the page.
class FocusCardSurface extends StatefulWidget {
  const FocusCardSurface({
    required this.appearance,
    required this.progress,
    required this.isBreak,
    required this.running,
    required this.child,
    this.reducedMotion,
    this.lowPower = false,
    this.animates = true,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final AppearancePreferences appearance;

  /// How far the current block has run, from 0 to 1.
  final double progress;

  final bool isBreak;

  /// Whether the timer is running. False freezes the frame exactly as it is.
  final bool running;

  final Widget child;

  /// Adds to the platform reduce-motion preference. True always reduces motion;
  /// false never re-enables motion the system asked to suppress.
  final bool? reducedMotion;

  /// Disables the clock and keeps the effect's still composition.
  final bool lowPower;

  /// False while the card is offscreen.
  final bool animates;

  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  State<FocusCardSurface> createState() => _FocusCardSurfaceState();
}

class _FocusCardSurfaceState extends State<FocusCardSurface>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  Duration _last = Duration.zero;
  bool _ticking = false;
  bool _systemReducedMotion = false;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;

  bool get _still =>
      widget.lowPower ||
      _reduceMotion ||
      widget.appearance.cardEffect == FocusCardEffect.off;

  bool get _reduced =>
      (widget.reducedMotion ?? false) || _systemReducedMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _systemReducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _reduceMotion = _reduced;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant FocusCardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reduceMotion = _reduced;
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _time.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final bool run =
        widget.animates && widget.running && !_still && _tickerEnabled;
    if (run && !_ticking) {
      final Ticker ticker = _ticker ??= createTicker(_onTick);
      _last = Duration.zero;
      ticker.start();
      _ticking = true;
    } else if (!run && _ticking) {
      _ticker?.stop();
      _ticking = false;
    }
  }

  void _onTick(Duration elapsed) {
    final Duration delta = elapsed - _last;
    if (delta <= Duration.zero) return;
    _last = elapsed;
    _time.value += delta.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final BorderRadius corner = BorderRadius.circular(widget.borderRadius);
    final FocusCardStyle style = widget.appearance.cardStyle;
    final FocusCardEffect effect = widget.appearance.cardEffect;
    final bool still = _still;
    final Widget? effectLayer = effect == FocusCardEffect.off
        ? null
        : _effectLayer(
            effect,
            dark ? Colors.white : scheme.primary,
            dark ? Colors.black : scheme.primary,
            still,
          );

    return DecoratedBox(
      decoration: focusCardDecoration(style, scheme, corner),
      child: ClipRRect(
        borderRadius: corner,
        child: Stack(
          children: <Widget>[
            if (effectLayer != null) Positioned.fill(child: effectLayer),
            if (style == FocusCardStyle.glass)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: focusCardSheenGradient(dark),
                    ),
                  ),
                ),
              ),
            Padding(padding: widget.padding, child: widget.child),
          ],
        ),
      ),
    );
  }

  Widget _effectLayer(
    FocusCardEffect effect,
    Color ink,
    Color shade,
    bool still,
  ) {
    Widget layer = ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (BuildContext context, double time, Widget? child) =>
          CustomPaint(
            painter: CardEffectPainter(
              effect: effect,
              time: time,
              progress: widget.progress,
              isBreak: widget.isBreak,
              active: !still,
              ink: ink,
              shade: shade,
            ),
            isComplex: true,
            willChange: !still,
            child: child,
          ),
      child: const SizedBox.expand(),
    );
    if (effect == FocusCardEffect.aurora || effect == FocusCardEffect.mesh) {
      final double sigma = effect == FocusCardEffect.aurora ? 16.0 : 18.0;
      layer = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: layer,
      );
    }
    return IgnorePointer(child: RepaintBoundary(child: layer));
  }
}
