import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/branding.dart';
import '../../core/storage/data_backup.dart';
import 'app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.onSave,
    required this.onExport,
    required this.onReplace,
    required this.onClear,
    this.notificationsAvailable = false,
    this.checkNotificationPermission,
    this.animationLab,
    this.developmentPacks,
    super.key,
  });

  final ValueNotifier<AppSettings> settings;
  final Future<void> Function(AppSettings) onSave;
  final Future<String> Function() onExport;
  final Future<void> Function(DataBackup) onReplace;
  final Future<void> Function() onClear;
  final bool notificationsAvailable;

  /// Optional host hook for the current Android notification permission.
  ///
  /// Saving still owns requesting access; this only reports existing state so
  /// the page never claims a permission it cannot verify.
  final Future<bool> Function()? checkNotificationPermission;

  final WidgetBuilder? animationLab;
  final WidgetBuilder? developmentPacks;

  static const focusDurationKey = ValueKey<String>('settings-focus-duration');
  static const shortBreakKey = ValueKey<String>('settings-short-break');
  static const longBreakKey = ValueKey<String>('settings-long-break');

  static Key themeOptionKey(ThemeMode mode) =>
      ValueKey<String>('settings-theme-${mode.name}');

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  Future<void> Function()? _retry;
  bool? _notificationsAllowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.notificationsAvailable) {
      unawaited(_refreshNotificationPermission());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.notificationsAvailable) {
      unawaited(_refreshNotificationPermission());
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notificationsAvailable &&
        (oldWidget.notificationsAvailable != widget.notificationsAvailable ||
            oldWidget.checkNotificationPermission !=
                widget.checkNotificationPermission)) {
      unawaited(_refreshNotificationPermission());
    }
  }

  Future<void> _refreshNotificationPermission() async {
    final check = widget.checkNotificationPermission;
    if (check == null) return;
    try {
      final allowed = await check();
      if (mounted) setState(() => _notificationsAllowed = allowed);
    } on Exception {
      if (mounted) setState(() => _notificationsAllowed = null);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String failure = 'Could not update local data.',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() {
          _busy = false;
          _retry = null;
        });
      }
    } on FormatException catch (error) {
      _fail(error.message, action);
    } on Exception {
      _fail(failure, action);
    }
  }

  void _fail(String message, Future<void> Function() action) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _retry = action;
    });
  }

  Future<void> _save(AppSettings next) => _run(
    () async {
      await widget.onSave(next);
      await _refreshNotificationPermission();
    },
    failure: 'Could not save settings. Try again.',
  );

  Future<void> _duration(
    String label,
    int current,
    int limit,
    AppSettings Function(int) change,
  ) async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => _DurationDialog(label, current, limit),
    );
    if (minutes != null && mounted) {
      await _save(change(minutes));
    }
  }

  Future<void> _export() => _run(
    () async {
      final text = await widget.onExport();
      if (!mounted) return;
      final backup = _decodeBackup(text);
      final copy = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Copy backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('The backup contains:'),
              const SizedBox(height: 10),
              if (backup != null)
                _BackupSummary(
                  backup: backup,
                  note:
                      'This text includes your focus history, including any '
                      'session labels and notes. Keep it private. It does not '
                      'include saved Focus or Clock presets, active clocks, or '
                      'installed companions.',
                )
              else
                const _Note(
                  'Timer defaults, feedback, appearance and focus history, '
                  'including labels and notes. Keep this text private. It '
                  'does not include saved presets, active clocks or '
                  'companions.',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Copy'),
            ),
          ],
        ),
      );
      if (copy != true || !mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      _message('Backup copied.');
    },
    failure: 'Could not copy the backup. Try again.',
  );

  DataBackup? _decodeBackup(String text) {
    try {
      return DataBackup.decode(text);
    } on FormatException {
      return null;
    } on Exception {
      return null;
    }
  }

  Future<void> _import() async {
    final backup = await showDialog<DataBackup>(
      context: context,
      builder: (context) => const _BackupDialog(),
    );
    if (backup == null || !mounted) return;
    await _run(
      () async {
        await widget.onReplace(backup);
        _message('Backup restored.');
      },
      failure: 'Could not restore the backup. Try again.',
    );
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ResetDialog(),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () async {
        await widget.onClear();
        _message('Local data cleared.');
      },
      failure: 'Could not clear local data. Try again.',
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _notificationSubtitle(bool enabled) {
    if (enabled && _notificationsAllowed == false) {
      return 'Blocked in Android settings. Allow notifications there, then '
          'try again.';
    }
    return 'Alerts when a timer ends, even outside the app.';
  }

  void _open(WidgetBuilder builder) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: builder));
  }

  Future<void> _showBuildDetails() async {
    final copy = await showDialog<bool>(
      context: context,
      builder: (context) => const _BuildDetailsDialog(),
    );
    if (copy != true || !mounted) return;
    await _run(
      () async {
        await Clipboard.setData(
          ClipboardData(text: Branding.displayVersion),
        );
        _message('Build ID copied.');
      },
      failure: 'Could not copy the build ID. Try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final animationLab = widget.animationLab;
    final developmentPacks = widget.developmentPacks;
    final hasLaboratory = animationLab != null || developmentPacks != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ValueListenableBuilder<AppSettings>(
          valueListenable: widget.settings,
          builder: (context, settings, _) {
            final retry = _retry;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_busy) const _BusyNotice(),
                if (_error != null)
                  _ErrorNotice(
                    message: _error!,
                    onRetry: retry == null ? null : () => _run(retry),
                  ),
                const _SectionHeader('Timer defaults', Icons.timer_outlined),
                _SettingsGroup(
                  children: [
                    _SettingsRow(
                      semanticsKey: SettingsPage.focusDurationKey,
                      title: 'Focus duration',
                      subtitle: 'Deep-work session length',
                      value: '${settings.focusMinutes} min',
                      enabled: !_busy,
                      onTap: _busy
                          ? null
                          : () => _duration(
                              'Focus duration',
                              settings.focusMinutes,
                              180,
                              (value) =>
                                  settings.copyWith(focusMinutes: value),
                            ),
                    ),
                    _SettingsRow(
                      semanticsKey: SettingsPage.shortBreakKey,
                      title: 'Short break',
                      subtitle: 'Recovery between focus sessions',
                      value: '${settings.shortBreakMinutes} min',
                      enabled: !_busy,
                      onTap: _busy
                          ? null
                          : () => _duration(
                              'Short break',
                              settings.shortBreakMinutes,
                              60,
                              (value) =>
                                  settings.copyWith(shortBreakMinutes: value),
                            ),
                    ),
                    _SettingsRow(
                      semanticsKey: SettingsPage.longBreakKey,
                      title: 'Long break',
                      subtitle: 'Longer recovery break',
                      value: '${settings.longBreakMinutes} min',
                      enabled: !_busy,
                      onTap: _busy
                          ? null
                          : () => _duration(
                              'Long break',
                              settings.longBreakMinutes,
                              60,
                              (value) =>
                                  settings.copyWith(longBreakMinutes: value),
                            ),
                    ),
                  ],
                ),
                if (widget.notificationsAvailable) ...[
                  const _SectionHeader(
                    'Notifications',
                    Icons.notifications_none,
                  ),
                  _SettingsGroup(
                    children: [
                      _SwitchRow(
                        title: 'Completion notifications',
                        subtitle: _notificationSubtitle(settings.notifications),
                        value: settings.notifications,
                        onChanged: _busy
                            ? null
                            : (value) => _save(
                                settings.copyWith(notifications: value),
                              ),
                      ),
                    ],
                  ),
                ],
                const _SectionHeader(
                  'Audio & haptics',
                  Icons.volume_up,
                ),
                _SettingsGroup(
                  children: [
                    _SwitchRow(
                      title: 'Sound',
                      subtitle:
                          'Timer completion and companion interactions.',
                      value: settings.sound,
                      onChanged: _busy
                          ? null
                          : (value) => _save(settings.copyWith(sound: value)),
                    ),
                    _SwitchRow(
                      title: 'Haptic feedback',
                      subtitle: 'Vibration for timer events.',
                      value: settings.haptics,
                      onChanged: _busy
                          ? null
                          : (value) => _save(settings.copyWith(haptics: value)),
                    ),
                  ],
                ),
                const _SectionHeader('Appearance', Icons.palette_outlined),
                _SettingsGroup(
                  children: [
                    _ThemeTile(
                      value: settings.themeMode,
                      enabled: !_busy,
                      onChanged: _busy
                          ? null
                          : (mode) => _save(
                              settings.copyWith(themeMode: mode),
                            ),
                    ),
                    _SwitchRow(
                      title: 'Reduce motion',
                      subtitle: 'Turn off non-essential animation.',
                      value: settings.reducedMotion,
                      onChanged: _busy
                          ? null
                          : (value) => _save(
                              settings.copyWith(reducedMotion: value),
                            ),
                    ),
                    _SwitchRow(
                      title: 'Low-power animation',
                      subtitle: 'Draw companion animation less often.',
                      value: settings.lowPower,
                      onChanged: _busy
                          ? null
                          : (value) => _save(
                              settings.copyWith(lowPower: value),
                            ),
                    ),
                  ],
                ),
                const _SectionHeader('Local data', Icons.folder_outlined),
                _SettingsGroup(
                  children: [
                    _SettingsRow(
                      icon: Icons.upload,
                      title: 'Export backup',
                      subtitle: 'Copy preferences and focus history as text.',
                      enabled: !_busy,
                      onTap: _busy ? null : _export,
                    ),
                    _SettingsRow(
                      icon: Icons.download,
                      title: 'Import backup',
                      subtitle: 'Replace local data from a backup.',
                      enabled: !_busy,
                      onTap: _busy ? null : _import,
                    ),
                    _SettingsRow(
                      icon: Icons.delete_outline,
                      title: 'Clear local data',
                      subtitle: 'Remove history, timers, packs and preferences.',
                      enabled: !_busy,
                      onTap: _busy ? null : _reset,
                    ),
                  ],
                ),
                const _SectionHeader('About', Icons.info_outline),
                _SettingsGroup(
                  children: [
                    _AboutRow(onShowDetails: _showBuildDetails),
                  ],
                ),
                if (hasLaboratory) ...[
                  const _SectionHeader('Laboratory', Icons.science_outlined),
                  _SettingsGroup(
                    children: [
                      if (animationLab != null)
                        _SettingsRow(
                          title: 'Animation laboratory',
                          subtitle: 'Motion and scene experiments.',
                          enabled: !_busy,
                          onTap: _busy ? null : () => _open(animationLab),
                        ),
                      if (developmentPacks != null)
                        _SettingsRow(
                          title: 'Development packs',
                          subtitle: 'Local development catalogue.',
                          enabled: !_busy,
                          onTap: _busy ? null : () => _open(developmentPacks),
                        ),
                    ],
                  ),
                  const _LabNote(),
                ],
              ],
            );
          },
        ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Semantics(
        header: true,
        child: Row(
          children: [
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

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(23),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
              children[index],
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.subtitle,
    this.value,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.semanticsKey,
  });

  final String title;
  final String subtitle;
  final String? value;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final Key? semanticsKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final valueText = value;
    final leadingIcon = icon;
    final foreground = enabled ? colors.onSurface : colors.onSurfaceVariant;
    final secondary = enabled
        ? colors.onSurfaceVariant
        : colors.onSurfaceVariant.withValues(alpha: 0.65);

    return Semantics(
      key: semanticsKey,
      container: true,
      button: onTap != null,
      enabled: enabled,
      label: '$title${valueText == null ? '' : ', $valueText'}. $subtitle',
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        focusColor: colors.primary.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stackValue =
                  valueText != null &&
                  (constraints.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21);
              return Row(
                children: [
                  if (leadingIcon != null) ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        leadingIcon,
                        size: 19,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                        if (stackValue) ...[
                          const SizedBox(height: 8),
                          _ValuePill(valueText, enabled: enabled),
                        ],
                      ],
                    ),
                  ),
                  if (valueText != null && !stackValue) ...[
                    const SizedBox(width: 12),
                    _ValuePill(valueText, enabled: enabled),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: secondary,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
        final selected = states.contains(WidgetState.selected);
        return Icon(
          selected ? Icons.check : Icons.close,
          size: 16,
          color: selected ? colors.primary : colors.surface,
        );
      }),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill(this.label, {this.enabled = true});

  final String label;
  final bool enabled;

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
          color: enabled ? colors.onSurface : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ThemeMode value;
  final bool enabled;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'System, Light or Dark',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ValuePill(_themeLabel(value), enabled: enabled),
            ],
          ),
          const SizedBox(height: 12),
          _ThemeSelector(
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ThemeMode value;
  final bool enabled;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labelSize = MediaQuery.textScalerOf(context).scale(14);
    final change = enabled ? onChanged : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical = constraints.maxWidth < 300 || labelSize > 21;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: vertical
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < _themeChoices.length; index++) ...[
                      if (index > 0) const SizedBox(height: 4),
                      _ThemeOption(
                        choice: _themeChoices[index],
                        selected: _themeChoices[index].mode == value,
                        enabled: change != null,
                        vertical: true,
                        onTap: change == null
                            ? null
                            : () => change(_themeChoices[index].mode),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    for (var index = 0; index < _themeChoices.length; index++) ...[
                      if (index > 0) const SizedBox(width: 4),
                      Expanded(
                        child: _ThemeOption(
                          choice: _themeChoices[index],
                          selected: _themeChoices[index].mode == value,
                          enabled: change != null,
                          vertical: false,
                          onTap: change == null
                              ? null
                              : () => change(_themeChoices[index].mode),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.vertical,
    required this.onTap,
  });

  final _ThemeChoice choice;
  final bool selected;
  final bool enabled;
  final bool vertical;
  final VoidCallback? onTap;

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
      key: SettingsPage.themeOptionKey(choice.mode),
      container: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: 'Theme: ${choice.label}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primary : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? Colors.transparent : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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

class _ThemeChoice {
  const _ThemeChoice(this.mode, this.label, this.icon);

  final ThemeMode mode;
  final String label;
  final IconData icon;
}

const _themeChoices = <_ThemeChoice>[
  _ThemeChoice(ThemeMode.system, 'System', Icons.brightness_auto),
  _ThemeChoice(ThemeMode.light, 'Light', Icons.light_mode),
  _ThemeChoice(ThemeMode.dark, 'Dark', Icons.dark_mode),
];

String _themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.onShowDetails});

  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = _buildSummary();
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Branding.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      button: true,
      label: '${Branding.name}. $summary. Show build details',
      onTap: onShowDetails,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackDetails =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 21;
          final details = TextButton.icon(
            onPressed: onShowDetails,
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('Details'),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            child: stackDetails
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity,
                      const SizedBox(height: 4),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 12),
                      details,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

String _buildSummary() {
  final build = Branding.buildNumber > 0
      ? 'build ${Branding.buildNumber}'
      : (Branding.buildId.isEmpty ? 'local build' : 'CI build');
  return 'Version ${Branding.version} · $build';
}

class _BackupSummary extends StatelessWidget {
  const _BackupSummary({required this.backup, required this.note});

  final DataBackup backup;
  final String note;

  @override
  Widget build(BuildContext context) {
    final settings = backup.settings;
    final count = backup.sessions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryLine(
          icon: Icons.timer_outlined,
          text:
              '${settings.focusMinutes} min focus, '
              '${settings.shortBreakMinutes} min short, '
              '${settings.longBreakMinutes} min long',
        ),
        _SummaryLine(
          icon: Icons.tune,
          text:
              'Feedback: notifications ${_onOff(settings.notifications)}, '
              'sound ${_onOff(settings.sound)}, '
              'haptics ${_onOff(settings.haptics)}',
        ),
        _SummaryLine(
          icon: Icons.palette_outlined,
          text:
              'Appearance: ${_themeLabel(settings.themeMode)}, '
              'reduced motion ${_onOff(settings.reducedMotion)}, '
              'low power ${_onOff(settings.lowPower)}',
        ),
        _SummaryLine(
          icon: Icons.history,
          text: '$count focus ${count == 1 ? 'session' : 'sessions'}',
        ),
        const SizedBox(height: 2),
        _Note(note),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
        ],
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

class _LabNote extends StatelessWidget {
  const _LabNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(
        'Development builds only.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BusyNotice extends StatelessWidget {
  const _BusyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.sync, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Updating local data…',
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
  const _ErrorNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onErrorContainer,
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _onOff(bool value) => value ? 'on' : 'off';

class _DurationDialog extends StatefulWidget {
  const _DurationDialog(this.label, this.current, this.limit);

  final String label;
  final int current;
  final int limit;

  @override
  State<_DurationDialog> createState() => _DurationDialogState();
}

class _DurationDialogState extends State<_DurationDialog> {
  late final _controller = TextEditingController(text: '${widget.current}');
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_controller.text.trim()));
    }
  }

  void _set(int minutes) {
    _controller.text = '$minutes';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = [5, 15, 25, 45, 60, 90]
        .where((minutes) => minutes <= widget.limit)
        .toList(growable: false);
    final current = int.tryParse(_controller.text.trim());

    return AlertDialog(
      scrollable: true,
      title: Text(widget.label),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Minutes',
                helperText: '1 to ${widget.limit}',
                suffixText: 'min',
                border: const OutlineInputBorder(),
              ),
              onFieldSubmitted: (_) => _submit(),
              validator: (text) {
                final value = int.tryParse(text?.trim() ?? '');
                return value == null || value < 1 || value > widget.limit
                    ? 'Enter 1 to ${widget.limit} minutes.'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            Text('Quick choices', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets)
                  ChoiceChip(
                    label: Text('$preset min'),
                    selected: current == preset,
                    onSelected: (_) => _set(preset),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _BackupDialog extends StatefulWidget {
  const _BackupDialog();

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final _controller = TextEditingController();
  DataBackup? _backup;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      setState(() {
        _backup = null;
        _error = null;
      });
      return;
    }
    try {
      final backup = DataBackup.decode(text);
      setState(() {
        _backup = backup;
        _error = null;
      });
    } on FormatException {
      _markInvalid();
    } on Exception {
      _markInvalid();
    }
  }

  void _markInvalid() {
    setState(() {
      _backup = null;
      _error = 'This is not a valid MinuteMeadow backup.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final backup = _backup;

    return AlertDialog(
      scrollable: true,
      title: const Text('Restore backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Paste backup text. Nothing changes until you restore.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 5,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              labelText: 'Backup text',
              hintText: 'Paste the copied backup here',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (backup != null) ...[
            const SizedBox(height: 12),
            const Text('This backup will replace:'),
            const SizedBox(height: 8),
            _BackupSummary(
              backup: backup,
              note:
                  'This also clears active timers and laps. Saved Focus and '
                  'Clock presets and installed companions stay on this device.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: backup == null
              ? null
              : () => Navigator.pop(context, backup),
          child: const Text('Restore backup'),
        ),
      ],
    );
  }
}

class _BuildDetailsDialog extends StatelessWidget {
  const _BuildDetailsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final identity = Branding.displayVersion;
    final local = Branding.buildId.isEmpty;

    return AlertDialog(
      scrollable: true,
      title: const Text('Build details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryLine(
            icon: Icons.apps,
            text: '${Branding.name} ${Branding.version}',
          ),
          _SummaryLine(
            icon: Icons.build,
            text: Branding.buildNumber > 0
                ? 'Build number ${Branding.buildNumber}'
                : 'Local development build',
          ),
          const SizedBox(height: 4),
          Text('Build ID', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: SelectableText(
              identity,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _Note(
            local
                ? 'Local builds have no CI identifier; the version above is '
                      'the complete identity.'
                : 'The full ID identifies the exact CI build. Copy it when '
                      'reporting a problem.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Copy ID'),
        ),
      ],
    );
  }
}

class _ResetDialog extends StatelessWidget {
  const _ResetDialog();

  @override
  Widget build(BuildContext context) {
    const defaults = AppSettings();
    return AlertDialog(
      scrollable: true,
      title: const Text('Clear local data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('This replaces local data with a clean setup:'),
          const SizedBox(height: 10),
          _SummaryLine(
            icon: Icons.timer_outlined,
            text:
                'Timer defaults return to ${defaults.focusMinutes} / '
                '${defaults.shortBreakMinutes} / '
                '${defaults.longBreakMinutes} minutes.',
          ),
          const _SummaryLine(
            icon: Icons.tune,
            text:
                'Preferences return to defaults: System theme, '
                'notifications off, sound and haptics on, reduced motion and '
                'low power off.',
          ),
          const _SummaryLine(
            icon: Icons.history,
            text: 'Focus history, active timers, clocks and laps are removed.',
          ),
          const _SummaryLine(
            icon: Icons.bookmark_border,
            text: 'Saved Focus and Clock presets are removed.',
          ),
          const _SummaryLine(
            icon: Icons.pets,
            text: 'Installed companions are removed.',
          ),
          const SizedBox(height: 4),
          const _Note(
            'This cannot be undone. A backup preserves preferences and '
            'history only, not presets or companions.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Clear data'),
        ),
      ],
    );
  }
}
