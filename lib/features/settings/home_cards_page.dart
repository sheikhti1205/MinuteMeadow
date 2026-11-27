import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/appearance_preferences.dart';
import '../../design/watch_timer_dial.dart';
import '../focus/cards/cards.dart';

/// Editor for the Focus home layout, card style, card animation and timer dial.
///
/// Every change stays in a local draft until Apply: Cancel leaves the saved
/// preferences untouched, and Reset puts the draft back to the product
/// defaults without saving. The sample card uses the real [FocusCardSurface],
/// so it is drawn by the same code as the timer. The page never mounts a
/// companion stage or a demo pack.
///
/// The wallpaper surface belongs to its own page; this page only links to it
/// through [onOpenWallpaper] and hides the row when no destination exists.
///
/// The sample card starts still. Playing it starts both the sample clock and
/// the card effect; pausing freezes both, so the editor stays calm until the
/// user asks for motion. `watchDial` reuses the shared [WatchTimerDial] inside
/// the same sample composition.
class HomeCardsPage extends StatefulWidget {
  const HomeCardsPage({
    required this.appearance,
    required this.onApply,
    this.lowPower = false,
    this.onOpenWallpaper,
    super.key,
  });

  /// The saved preferences at the moment the editor was opened.
  final AppearancePreferences appearance;

  /// Called with the draft when the user applies it.
  ///
  /// It must complete only after the value has been stored. Throwing keeps the
  /// editor open and shows its error, so the page never reports a save that
  /// did not happen.
  final Future<void> Function(AppearancePreferences appearance) onApply;

  /// Keeps the card sample still, matching the saved low-power preference.
  final bool lowPower;

  /// Opens the wallpaper surface. When null the row is hidden, so the editor
  /// never shows a button with nowhere to go.
  final VoidCallback? onOpenWallpaper;

  static const Key resetKey = Key('home-cards-reset');
  static const Key cancelKey = Key('home-cards-cancel');
  static const Key applyKey = Key('home-cards-apply');
  static const Key previewKey = Key('home-cards-preview');
  static const Key sampleMotionKey = Key('home-cards-sample-motion');
  static const Key sampleDialKey = Key('home-cards-sample-dial');
  static const Key wallpaperKey = Key('home-cards-wallpaper');
  static const Key layoutKey = Key('home-cards-layout');
  static const Key styleKey = Key('home-cards-style');
  static const Key animationKey = Key('home-cards-animation');

  static Key layoutOptionKey(HomeLayout layout) =>
      ValueKey<String>('home-cards-layout-${layout.name}');

  static Key styleOptionKey(FocusCardStyle style) =>
      ValueKey<String>('home-cards-style-${style.name}');

  static Key effectOptionKey(FocusCardEffect effect) =>
      ValueKey<String>('home-cards-effect-${effect.name}');

  static Key dialOptionKey(bool watchDial) =>
      ValueKey<String>('home-cards-dial-${watchDial ? 'watch' : 'digital'}');

  @override
  State<HomeCardsPage> createState() => _HomeCardsPageState();
}

class _HomeCardsPageState extends State<HomeCardsPage> {
  /// How long the sample block takes to run, so effects that follow progress
  /// can be seen working.
  static const int _sampleSeconds = 40;
  static const int _sampleMinutes = 25;

  late final AppearancePreferences _initial = widget.appearance;
  late AppearancePreferences _draft = widget.appearance;
  double _progress = 0.15;
  Timer? _clock;
  bool _previewRunning = false;
  bool _saving = false;
  String? _error;

  /// Starts or stops the sample clock. A stopped sample keeps its position, so
  /// the card and the readout freeze on the same frame.
  void _syncClock() {
    if (_previewRunning) {
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _progress = (_progress + 1 / _sampleSeconds) % 1;
        });
      });
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  void _togglePreviewMotion() {
    setState(() {
      _previewRunning = !_previewRunning;
    });
    _syncClock();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  bool get _dirty =>
      _draft.homeLayout != _initial.homeLayout ||
      _draft.cardStyle != _initial.cardStyle ||
      _draft.cardEffect != _initial.cardEffect ||
      _draft.watchDial != _initial.watchDial;

  void _selectLayout(HomeLayout layout) {
    if (_saving || _draft.homeLayout == layout) return;
    setState(() {
      _draft = _draft.copyWith(homeLayout: layout);
      _error = null;
    });
  }

  void _selectStyle(FocusCardStyle style) {
    if (_saving || _draft.cardStyle == style) return;
    setState(() {
      _draft = _draft.copyWith(cardStyle: style);
      _error = null;
    });
  }

  void _selectEffect(FocusCardEffect effect) {
    if (_saving || _draft.cardEffect == effect) return;
    setState(() {
      _draft = _draft.copyWith(cardEffect: effect);
      _error = null;
    });
  }

  void _selectDial(bool watchDial) {
    if (_saving || _draft.watchDial == watchDial) return;
    setState(() {
      _draft = _draft.copyWith(watchDial: watchDial);
      _error = null;
    });
  }

  /// Restores only the choices this page owns. Wallpaper, palette, fonts and
  /// theme mode are another surface's draft and stay as they are.
  void _reset() {
    if (_saving) return;
    setState(() {
      _draft = _draft.copyWith(
        homeLayout: HomeLayout.classic,
        cardStyle: FocusCardStyle.filled,
        cardEffect: FocusCardEffect.off,
        watchDial: false,
      );
      _error = null;
    });
  }

  Future<void> _apply() async {
    if (_saving || !_dirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onApply(_draft);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save Home & Cards. Try again.';
      });
    }
  }

  String _clockLabel() {
    final int total = _sampleMinutes * 60;
    final int left = (total * (1 - _progress)).round();
    final String minutes = (left ~/ 60).toString().padLeft(2, '0');
    final String seconds = (left % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Home & Cards')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_saving) const _BusyNotice(),
                        if (_error != null) _ErrorNotice(message: _error!),
                        const _SectionHeader(
                          'Selected card',
                          Icons.timer_outlined,
                        ),
                        _preview(theme, scheme, reduceMotion),
                        if (reduceMotion || widget.lowPower)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                            child: _StillNote(),
                          ),
                        const _SectionHeader(
                          'Home layout',
                          Icons.space_dashboard_outlined,
                        ),
                        _layoutRow(scheme),
                        const _SectionHeader('Card style', Icons.style_outlined),
                        _styleRow(scheme),
                        const _SectionHeader(
                          'Card animation',
                          Icons.auto_awesome_outlined,
                        ),
                        _effectGrid(scheme),
                        const _SectionHeader(
                          'Timer dial',
                          Icons.watch_later_outlined,
                        ),
                        _dialRow(scheme),
                        if (widget.onOpenWallpaper != null)
                          _wallpaperRow(scheme),
                        const SizedBox(height: 12),
                        Text(
                          'Nothing changes until you tap Apply. Reset restores '
                          'the product defaults in this draft only.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme, ColorScheme scheme, bool reduceMotion) {
    final TextTheme text = theme.textTheme;
    final bool motion = !reduceMotion && !widget.lowPower;
    final Widget readout = Text(
      _clockLabel(),
      style: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1,
        letterSpacing: -0.5,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    return Semantics(
      key: HomeCardsPage.previewKey,
      container: true,
      label:
          'Home card preview: ${_draft.cardStyle.label} card, '
          '${_draft.cardEffect.label} animation',
      child: FocusCardSurface(
        appearance: _draft,
        progress: _progress,
        isBreak: false,
        running: _previewRunning,
        lowPower: widget.lowPower,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.onSurface,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Focusing',
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (motion)
                  IconButton(
                    key: HomeCardsPage.sampleMotionKey,
                    tooltip: _previewRunning ? 'Pause sample' : 'Play sample',
                    onPressed: _togglePreviewMotion,
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    icon: Icon(
                      _previewRunning
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  '$_sampleMinutes min',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_draft.watchDial)
              Center(
                child: WatchTimerDial(
                  key: HomeCardsPage.sampleDialKey,
                  progress: _progress,
                  diameter: 168,
                  child: readout,
                ),
              )
            else
              readout,
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              !motion
                  ? 'A focus block, drawn with your draft settings.'
                  : _previewRunning
                  ? 'A running focus block, drawn with your draft settings.'
                  : 'The sample is still. Play it to watch the card move.',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layoutRow(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < HomeLayout.values.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: _layoutTile(HomeLayout.values[index], scheme)),
        ],
      ],
    );
  }

  Widget _layoutTile(HomeLayout layout, ColorScheme scheme) {
    final bool selected = _draft.homeLayout == layout;
    return Material(
      key: HomeCardsPage.layoutOptionKey(layout),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !_saving,
        label:
            'Home layout: ${layout.label}. '
            '${_layoutDescription(layout)}',
        excludeSemantics: true,
        onTap: _saving ? null : () => _selectLayout(layout),
        child: InkWell(
          onTap: _saving ? null : () => _selectLayout(layout),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    height: 118,
                    child: HomeLayoutSketch(layout: layout),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        layout.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (selected) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _layoutDescription(layout),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _styleRow(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < FocusCardStyle.values.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: _styleTile(FocusCardStyle.values[index], scheme),
          ),
        ],
      ],
    );
  }

  Widget _styleTile(FocusCardStyle style, ColorScheme scheme) {
    final bool selected = _draft.cardStyle == style;
    return Material(
      key: HomeCardsPage.styleOptionKey(style),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !_saving,
        label: 'Card style: ${style.label}',
        excludeSemantics: true,
        onTap: _saving ? null : () => _selectStyle(style),
        child: InkWell(
          onTap: _saving ? null : () => _selectStyle(style),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _StyleSwatch(style: style, scheme: scheme),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        style.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (selected) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _effectGrid(ColorScheme scheme) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final FocusCardEffect effect in FocusCardEffect.values)
              SizedBox(width: width, child: _effectTile(effect, scheme)),
          ],
        );
      },
    );
  }

  Widget _effectTile(FocusCardEffect effect, ColorScheme scheme) {
    final bool selected = _draft.cardEffect == effect;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      key: HomeCardsPage.effectOptionKey(effect),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !_saving,
        label: 'Card animation: ${effect.label}',
        excludeSemantics: true,
        onTap: _saving ? null : () => _selectEffect(effect),
        child: InkWell(
          onTap: _saving ? null : () => _selectEffect(effect),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                _EffectThumbnail(
                  style: _draft.cardStyle,
                  effect: effect,
                  scheme: scheme,
                  dark: dark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    effect.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialRow(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _dialTile(false, scheme)),
        const SizedBox(width: 10),
        Expanded(child: _dialTile(true, scheme)),
      ],
    );
  }

  Widget _dialTile(bool watchDial, ColorScheme scheme) {
    final bool selected = _draft.watchDial == watchDial;
    final String label = watchDial ? 'Watch dial' : 'Digital';
    return Material(
      key: HomeCardsPage.dialOptionKey(watchDial),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        enabled: !_saving,
        label: 'Timer dial: $label',
        excludeSemantics: true,
        onTap: _saving ? null : () => _selectDial(watchDial),
        child: InkWell(
          onTap: _saving ? null : () => _selectDial(watchDial),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wallpaperRow(ColorScheme scheme) {
    final bool enabled = !_saving;
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Material(
        key: HomeCardsPage.wallpaperKey,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          container: true,
          button: true,
          enabled: enabled,
          label: 'Wallpaper. Built-in scenes or your own photo.',
          excludeSemantics: true,
          onTap: enabled ? widget.onOpenWallpaper : null,
          child: InkWell(
            onTap: enabled ? widget.onOpenWallpaper : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.wallpaper,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Wallpaper',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Built-in scenes or your own photo',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              TextButton.icon(
                key: HomeCardsPage.resetKey,
                onPressed: _saving ? null : _reset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset'),
              ),
              TextButton(
                key: HomeCardsPage.cancelKey,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: HomeCardsPage.applyKey,
                onPressed: _saving || !_dirty ? null : _apply,
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.style, required this.scheme});

  final FocusCardStyle style;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corner = BorderRadius.circular(12);
    final bool glass = style == FocusCardStyle.glass;
    return Container(
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: focusCardDecoration(style, scheme, corner),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (glass)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: focusCardSheenGradient(
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Container(
                  width: 26,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 46,
                  height: 9,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectThumbnail extends StatelessWidget {
  const _EffectThumbnail({
    required this.style,
    required this.effect,
    required this.scheme,
    required this.dark,
  });

  final FocusCardStyle style;
  final FocusCardEffect effect;
  final ColorScheme scheme;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corner = BorderRadius.circular(10);
    return Container(
      width: 56,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: focusCardDecoration(style, scheme, corner),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (effect != FocusCardEffect.off)
            CustomPaint(
              painter: CardEffectPainter(
                effect: effect,
                time: 7.0,
                progress: 0.55,
                isBreak: false,
                active: true,
                ink: dark ? Colors.white : scheme.primary,
                shade: dark ? Colors.black : scheme.primary,
              ),
            ),
          if (style == FocusCardStyle.glass)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: focusCardSheenGradient(dark),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Semantics(
        header: true,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StillNote extends StatelessWidget {
  const _StillNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      'Reduced motion or low-power animation is on, so the card stays still '
      'here and on the timer.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _BusyNotice extends StatelessWidget {
  const _BusyNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.sync, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Saving Home & Cards…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _layoutDescription(HomeLayout layout) => switch (layout) {
  HomeLayout.classic => 'The original stack',
  HomeLayout.refined => 'A calmer ring',
  HomeLayout.studio => 'A dial and a dock',
};
