import 'package:flutter/material.dart';

import '../../design/appearance_preferences.dart';
import '../../design/companion_theme.dart';
import '../focus/cards/cards.dart';
import 'app_settings.dart';

/// The theme fields the Theme & Colors editor owns.
///
/// The editor never saves a whole [AppearancePreferences]. [mergeInto]
/// replaces only these fields on the settings it is given, so the Home & Cards
/// layout, card style and effect, wallpaper and watch dial, and every timer and
/// alert setting keep the value stored when Apply runs.
@immutable
class ThemeSelection {
  const ThemeSelection({
    this.mode = ThemeMode.system,
    this.amoled = false,
    this.palette = AppPalette.grayscale,
    this.customAccent,
    this.customSurface,
    this.appFont = AppFont.system,
    this.timerFont = AppFont.system,
  });

  /// Reads only the owned fields out of [settings].
  factory ThemeSelection.fromSettings(AppSettings settings) {
    final appearance = settings.appearance;
    return ThemeSelection(
      mode: settings.themeMode,
      amoled: appearance.amoled,
      palette: appearance.palette,
      customAccent: appearance.customAccent,
      customSurface: appearance.customSurface,
      appFont: appearance.appFont,
      timerFont: appearance.timerFont,
    );
  }

  /// The product default: System mode and the original grayscale chrome.
  static const defaults = ThemeSelection();

  final ThemeMode mode;
  final bool amoled;
  final AppPalette palette;
  final Color? customAccent;
  final Color? customSurface;
  final AppFont appFont;
  final AppFont timerFont;

  ThemeSelection copyWith({
    ThemeMode? mode,
    bool? amoled,
    AppPalette? palette,
    Color? customAccent,
    bool clearCustomAccent = false,
    Color? customSurface,
    bool clearCustomSurface = false,
    AppFont? appFont,
    AppFont? timerFont,
  }) => ThemeSelection(
    mode: mode ?? this.mode,
    amoled: amoled ?? this.amoled,
    palette: palette ?? this.palette,
    customAccent: clearCustomAccent
        ? null
        : (customAccent ?? this.customAccent),
    customSurface: clearCustomSurface
        ? null
        : (customSurface ?? this.customSurface),
    appFont: appFont ?? this.appFont,
    timerFont: timerFont ?? this.timerFont,
  );

  /// Applies only the owned fields to [base].
  AppearancePreferences applyTo(AppearancePreferences base) => base.copyWith(
    amoled: amoled,
    palette: palette,
    customAccent: customAccent,
    clearCustomAccent: customAccent == null,
    customSurface: customSurface,
    clearCustomSurface: customSurface == null,
    appFont: appFont,
    timerFont: timerFont,
  );

  /// Merges the owned fields into [base], leaving everything else untouched.
  AppSettings mergeInto(AppSettings base) =>
      base.copyWith(themeMode: mode, appearance: applyTo(base.appearance));

  @override
  bool operator ==(Object other) =>
      other is ThemeSelection &&
      other.mode == mode &&
      other.amoled == amoled &&
      other.palette == palette &&
      other.customAccent == customAccent &&
      other.customSurface == customSurface &&
      other.appFont == appFont &&
      other.timerFont == timerFont;

  @override
  int get hashCode => Object.hash(
    mode,
    amoled,
    palette,
    customAccent,
    customSurface,
    appFont,
    timerFont,
  );
}

/// Draft editor for theme mode, AMOLED, colour palettes and fonts.
///
/// The editor owns a private [ThemeSelection]. Mode, AMOLED, colour and font
/// changes only rebuild the preview; [onSave] runs exactly once when Apply is
/// pressed. Back and Cancel leave the stored settings untouched, and Reset
/// returns this editor's own fields to the product default without touching the
/// home layout, card choices, wallpaper, watch dial or alerts.
class ThemeColorsPage extends StatefulWidget {
  const ThemeColorsPage({
    required this.settings,
    required this.onSave,
    this.systemSeed,
    this.latestSettings,
    super.key,
  });

  /// Shown when [AppPalette.system] has no platform seed, so the choice is
  /// disabled with a stated reason instead of silently doing nothing.
  static const systemSeedUnavailableMessage =
      'System colours need a platform seed. This build has none, so '
      'Grayscale is used.';

  static Key paletteChoiceKey(AppPalette palette) =>
      ValueKey<String>('theme-palette-${palette.name}');

  /// Settings captured when the editor opens.
  final AppSettings settings;

  /// Saves the merged settings. The editor closes only after this completes.
  final Future<void> Function(AppSettings) onSave;

  /// Optional platform colour seed for [AppPalette.system].
  ///
  /// The host supplies a seed when the platform exposes one. A null seed
  /// disables the System palette in this editor.
  final Color? systemSeed;

  /// Supplies the newest stored settings when Apply runs.
  ///
  /// Merging against it keeps changes made elsewhere while the editor was open.
  /// The editor falls back to [settings] when this is omitted.
  final AppSettings Function()? latestSettings;

  static Route<void> route({
    required AppSettings settings,
    required Future<void> Function(AppSettings) onSave,
    Color? systemSeed,
    AppSettings Function()? latestSettings,
  }) => MaterialPageRoute<void>(
    builder: (_) => ThemeColorsPage(
      settings: settings,
      onSave: onSave,
      systemSeed: systemSeed,
      latestSettings: latestSettings,
    ),
  );

  @override
  State<ThemeColorsPage> createState() => _ThemeColorsPageState();
}

class _ThemeColorsPageState extends State<ThemeColorsPage> {
  late ThemeSelection _selection;
  bool _saving = false;
  String? _error;

  bool get _systemPaletteAvailable => widget.systemSeed != null;

  /// The saved card choices still shape the preview; only the theme fields come
  /// from the draft.
  AppearancePreferences get _previewAppearance =>
      _selection.applyTo(widget.settings.appearance);

  @override
  void initState() {
    super.initState();
    _selection = ThemeSelection.fromSettings(widget.settings);
  }

  void _update(ThemeSelection next) {
    setState(() {
      _selection = next;
      _error = null;
    });
  }

  /// Clears this editor's fields only.
  void _reset() => _update(ThemeSelection.defaults);

  Future<void> _apply() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final base = widget.latestSettings?.call() ?? widget.settings;
      await widget.onSave(_selection.mergeInto(base));
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
      return;
    } on Exception {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save appearance. Try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _pickAccent() async {
    final choice = await showDialog<_ColorSelection>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        title: 'Custom accent',
        initial:
            _selection.customAccent ?? Theme.of(context).colorScheme.primary,
      ),
    );
    if (choice == null || !mounted) return;
    _update(
      _selection.copyWith(
        customAccent: choice.color,
        clearCustomAccent: choice.color == null,
      ),
    );
  }

  Future<void> _pickSurface() async {
    final choice = await showDialog<_ColorSelection>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        title: 'Custom surface',
        initial:
            _selection.customSurface ?? Theme.of(context).colorScheme.surface,
      ),
    );
    if (choice == null || !mounted) return;
    _update(
      _selection.copyWith(
        customSurface: choice.color,
        clearCustomSurface: choice.color == null,
      ),
    );
  }

  Brightness get _brightness => switch (_selection.mode) {
    ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
  };

  @override
  Widget build(BuildContext context) {
    final appearance = _previewAppearance;
    final previewTheme = CompanionTheme.forAppearance(
      appearance,
      brightness: _brightness,
      systemSeed: widget.systemSeed,
    );
    final enabled = !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Theme & Colors')),
      body: SafeArea(
        child: Column(
          children: [
            if (_error case final String message)
              _ErrorBar(
                message: message,
                onDismiss: () => setState(() => _error = null),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _ThemePreview(
                    theme: previewTheme,
                    appearance: appearance,
                    mode: _selection.mode,
                  ),
                  const _EditorSection('Theme'),
                  _ModeChoices(
                    value: _selection.mode,
                    enabled: enabled,
                    onChanged: (mode) =>
                        _update(_selection.copyWith(mode: mode)),
                  ),
                  const _EditorSection('Display'),
                  _AmoledTile(
                    value: _selection.amoled,
                    enabled: enabled,
                    onChanged: (value) =>
                        _update(_selection.copyWith(amoled: value)),
                  ),
                  const _EditorSection('Colour & palette'),
                  _PaletteChoices(
                    value: _selection.palette,
                    enabled: enabled,
                    systemSeedAvailable: _systemPaletteAvailable,
                    onChanged: (palette) =>
                        _update(_selection.copyWith(palette: palette)),
                  ),
                  if (!_systemPaletteAvailable) ...[
                    const SizedBox(height: 8),
                    const _Note(ThemeColorsPage.systemSeedUnavailableMessage),
                  ],
                  const SizedBox(height: 10),
                  _ColorRow(
                    title: 'Custom accent',
                    value: _selection.customAccent,
                    enabled: enabled,
                    onTap: _pickAccent,
                  ),
                  const SizedBox(height: 8),
                  _ColorRow(
                    title: 'Custom surface',
                    value: _selection.customSurface,
                    enabled: enabled,
                    onTap: _pickSurface,
                  ),
                  const _EditorSection('Fonts'),
                  _FontChoices(
                    label: 'App font',
                    value: _selection.appFont,
                    enabled: enabled,
                    onChanged: (font) =>
                        _update(_selection.copyWith(appFont: font)),
                  ),
                  const SizedBox(height: 12),
                  _FontChoices(
                    label: 'Timer font',
                    value: _selection.timerFont,
                    enabled: enabled,
                    onChanged: (font) =>
                        _update(_selection.copyWith(timerFont: font)),
                  ),
                  const SizedBox(height: 8),
                  const _Note(
                    'Fonts use families already installed on your device. '
                    'No fonts are downloaded.',
                  ),
                ],
              ),
            ),
            _EditorFooter(
              busy: _saving,
              onReset: _saving ? null : _reset,
              onCancel: _saving
                  ? null
                  : () => Navigator.of(context).maybePop(),
              onApply: _saving ? null : _apply,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ModeChoice {
  const _ModeChoice(this.mode, this.label, this.icon);

  final ThemeMode mode;
  final String label;
  final IconData icon;
}

const _modeChoices = <_ModeChoice>[
  _ModeChoice(ThemeMode.system, 'System', Icons.brightness_auto),
  _ModeChoice(ThemeMode.light, 'Light', Icons.light_mode),
  _ModeChoice(ThemeMode.dark, 'Dark', Icons.dark_mode),
];

class _ModeChoices extends StatelessWidget {
  const _ModeChoices({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ThemeMode value;
  final bool enabled;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelSize = MediaQuery.textScalerOf(context).scale(14);
    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical = constraints.maxWidth < 300 || labelSize > 21;
        if (vertical) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < _modeChoices.length; index++) ...[
                if (index > 0) const SizedBox(height: 6),
                _ThemeModeOption(
                  choice: _modeChoices[index],
                  selected: _modeChoices[index].mode == value,
                  enabled: enabled,
                  vertical: true,
                  onTap: () => onChanged(_modeChoices[index].mode),
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < _modeChoices.length; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              Expanded(
                child: _ThemeModeOption(
                  choice: _modeChoices[index],
                  selected: _modeChoices[index].mode == value,
                  enabled: enabled,
                  vertical: false,
                  onTap: () => onChanged(_modeChoices[index].mode),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.vertical,
    required this.onTap,
  });

  final _ModeChoice choice;
  final bool selected;
  final bool enabled;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected
        ? colors.onPrimary
        : (enabled ? colors.onSurface : colors.onSurfaceVariant);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: foreground,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    final content = vertical
        ? Row(
            children: [
              Icon(choice.icon, size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(child: Text(choice.label, style: labelStyle)),
              if (selected) Icon(Icons.check, size: 18, color: foreground),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check : choice.icon,
                size: 20,
                color: foreground,
              ),
              const SizedBox(height: 4),
              Text(
                choice.label,
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
            ],
          );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Theme: ${choice.label}',
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primary : colors.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? Colors.transparent : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          focusColor: colors.primary.withValues(alpha: 0.12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: vertical ? 12 : 6,
                vertical: 8,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _AmoledTile extends StatelessWidget {
  const _AmoledTile({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void toggle() => onChanged(!value);
    return Semantics(
      container: true,
      button: true,
      toggled: value,
      enabled: enabled,
      label: 'AMOLED',
      onTap: enabled ? toggle : null,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? toggle : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AMOLED',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'True black surfaces in dark mode.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: enabled ? onChanged : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteChoices extends StatelessWidget {
  const _PaletteChoices({
    required this.value,
    required this.enabled,
    required this.systemSeedAvailable,
    required this.onChanged,
  });

  final AppPalette value;
  final bool enabled;
  final bool systemSeedAvailable;
  final ValueChanged<AppPalette> onChanged;

  bool _available(AppPalette palette) =>
      palette != AppPalette.system || systemSeedAvailable;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final palette in AppPalette.values)
          ChoiceChip(
            key: ThemeColorsPage.paletteChoiceKey(palette),
            label: Text(palette.label),
            selected: palette == value,
            avatar: palette.seed == null
                ? null
                : CircleAvatar(radius: 8, backgroundColor: palette.seed),
            onSelected: enabled && _available(palette)
                ? (_) => onChanged(palette)
                : null,
          ),
      ],
    );
  }
}

class _FontChoices extends StatelessWidget {
  const _FontChoices({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final AppFont value;
  final bool enabled;
  final ValueChanged<AppFont> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final font in AppFont.values)
              ChoiceChip(
                label: Text(font.label),
                selected: font == value,
                onSelected: enabled ? (_) => onChanged(font) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final Color? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final valueText = value == null ? 'Default' : _hexColor(value!);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: '$title, $valueText',
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: value ?? colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        valueText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.theme,
    required this.appearance,
    required this.mode,
  });

  final ThemeData theme;
  final AppearancePreferences appearance;
  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = theme.colorScheme;
    final cardColor = switch (appearance.cardStyle) {
      FocusCardStyle.filled => colors.surfaceContainerLow,
      FocusCardStyle.outlined => colors.surface,
      FocusCardStyle.glass => colors.surfaceContainerHigh.withValues(
        alpha: 0.72,
      ),
    };
    final borderColor = switch (appearance.cardStyle) {
      FocusCardStyle.filled => colors.outlineVariant,
      FocusCardStyle.outlined => colors.outline,
      FocusCardStyle.glass => colors.outline.withValues(alpha: 0.55),
    };
    final label =
        'Theme preview: ${_modeLabel(mode)}, '
        '${appearance.palette.label} palette, '
        '${appearance.appFont.label} app font, '
        '${appearance.timerFont.label} timer font';

    return Semantics(
      container: true,
      label: label,
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) {
            final textTheme = Theme.of(context).textTheme;
            // A compact sample card. Clamping keeps its fixed height intact at
            // large text scales; the page itself follows the user's scale.
            final sample = IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  height: 220,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (appearance.cardEffect != FocusCardEffect.off)
                        CustomPaint(
                          painter: CardEffectPainter(
                            effect: appearance.cardEffect,
                            time: 6.0,
                            progress: 0.35,
                            isBreak: false,
                            active: true,
                            ink: colors.onSurface,
                            shade: colors.onSurfaceVariant,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'FOCUS',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                _PreviewPill(label: '25 min'),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              '25:00',
                              textAlign: TextAlign.center,
                              style: textTheme.displayLarge?.copyWith(
                                fontSize: 44,
                                height: 1,
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'One quiet minute at a time',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Text(
                                'Start focus',
                                style: textTheme.labelLarge?.copyWith(
                                  color: colors.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: sample,
            );
          },
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: colors.errorContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.error.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: colors.onErrorContainer,
              ),
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
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 18),
                color: colors.onErrorContainer,
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.busy,
    required this.onReset,
    required this.onCancel,
    required this.onApply,
  });

  final bool busy;
  final VoidCallback? onReset;
  final VoidCallback? onCancel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset to default'),
              ),
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: onApply,
                child: busy ? const Text('Saving…') : const Text('Apply'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSelection {
  const _ColorSelection(this.color);

  final Color? color;
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _color;

  @override
  void initState() {
    super.initState();
    _color = HSVColor.fromColor(widget.initial);
  }

  void _set(HSVColor color) => setState(() => _color = color);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = _color.toColor();
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.outline),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _hexColor(color),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ColorSlider(
            label: 'Hue',
            value: _color.hue,
            min: 0,
            max: 360,
            divisions: 360,
            display: '${_color.hue.round()}°',
            onChanged: (value) => _set(_color.withHue(value)),
          ),
          _ColorSlider(
            label: 'Saturation',
            value: _color.saturation,
            min: 0,
            max: 1,
            divisions: 100,
            display: '${(_color.saturation * 100).round()}%',
            onChanged: (value) => _set(_color.withSaturation(value)),
          ),
          _ColorSlider(
            label: 'Brightness',
            value: _color.value,
            min: 0,
            max: 1,
            divisions: 100,
            display: '${(_color.value * 100).round()}%',
            onChanged: (value) => _set(_color.withValue(value)),
          ),
          const SizedBox(height: 8),
          Text('Presets', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final preset in _colorPresets)
                IconButton(
                  onPressed: () => _set(HSVColor.fromColor(preset)),
                  tooltip: _hexColor(preset),
                  iconSize: 28,
                  icon: Icon(
                    preset.toARGB32() == color.toARGB32()
                        ? Icons.check_circle
                        : Icons.circle,
                    color: preset,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _ColorSelection(null)),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ColorSelection(color)),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.labelLarge),
            ),
            Text(display, style: theme.textTheme.labelMedium),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

const _colorPresets = <Color>[
  Color(0xFF7A8B6F),
  Color(0xFFA85A42),
  Color(0xFF3F6F87),
  Color(0xFF6C5C87),
  Color(0xFFD4A34A),
  Color(0xFF8C3A4A),
  Color(0xFF2E2E2E),
  Color(0xFFF2F2F2),
];

String _modeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

String _hexColor(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
