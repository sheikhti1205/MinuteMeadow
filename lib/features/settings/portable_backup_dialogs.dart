import 'package:flutter/material.dart';

import '../../core/storage/data_backup.dart';

/// The confirmed portable-file export choice.
///
/// The dialog only returns a decision. The caller builds the [DataBackup] with
/// [includePresets] set, encodes it and writes the file afterwards, so nothing
/// reaches storage before the user confirms.
class PortableBackupExportChoice {
  const PortableBackupExportChoice({required this.includePresets});

  /// Whether the caller should attach saved Focus and Clock presets.
  final bool includePresets;
}

/// Shows the compact "Save backup" preview and waits for confirmation.
///
/// Returns the confirmed choice, or null when the user cancels. [sessionCount]
/// and the optional preset counts only describe what the file will contain;
/// the dialog never reads or writes data. Pass the preset counts from the
/// current stores when they are known so the checkbox can be disabled when
/// there is nothing to include.
Future<PortableBackupExportChoice?> showPortableBackupExportDialog(
  BuildContext context, {
  required int sessionCount,
  int? focusPresetCount,
  int? clockPresetCount,
}) {
  return showDialog<PortableBackupExportChoice>(
    context: context,
    builder: (BuildContext context) => PortableBackupExportDialog(
      sessionCount: sessionCount,
      focusPresetCount: focusPresetCount,
      clockPresetCount: clockPresetCount,
    ),
  );
}

/// Compact Material preview for a portable-file save.
///
/// Saved presets are an explicit, default-off opt-in. Photos, companion packs,
/// active timers, one-off plans and laps are never part of the file.
class PortableBackupExportDialog extends StatefulWidget {
  const PortableBackupExportDialog({
    required this.sessionCount,
    this.focusPresetCount,
    this.clockPresetCount,
    super.key,
  });

  final int sessionCount;

  /// The number of saved Focus presets, or null when the caller cannot count
  /// them yet. Null keeps the preset opt-in available.
  final int? focusPresetCount;

  /// The number of saved Clock presets, or null when unknown.
  final int? clockPresetCount;

  static const includePresetsKey = ValueKey<String>(
    'portable-backup-include-presets',
  );
  static const confirmKey = ValueKey<String>('portable-backup-save');

  @override
  State<PortableBackupExportDialog> createState() =>
      _PortableBackupExportDialogState();
}

class _PortableBackupExportDialogState
    extends State<PortableBackupExportDialog> {
  bool _includePresets = false;

  bool get _countsKnown =>
      widget.focusPresetCount != null && widget.clockPresetCount != null;

  int get _presetTotal =>
      (widget.focusPresetCount ?? 0) + (widget.clockPresetCount ?? 0);

  bool get _presetsAvailable => !_countsKnown || _presetTotal > 0;

  String get _presetSubtitle {
    if (!_countsKnown) {
      return 'Saved Focus and Clock presets you created.';
    }
    final focus = widget.focusPresetCount!;
    final clock = widget.clockPresetCount!;
    if (_presetTotal == 0) return 'No saved presets on this device.';
    if (focus == 0) return '$clock Clock ${_presetWord(clock)} saved.';
    if (clock == 0) return '$focus Focus ${_presetWord(focus)} saved.';
    return '$focus Focus and $clock Clock ${_presetWord(_presetTotal)} saved.';
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sessionCount;
    final include = _includePresets && _presetsAvailable;

    return AlertDialog(
      scrollable: true,
      title: const Text('Save backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('The file will include:'),
          const SizedBox(height: 10),
          const _SummaryLine(
            icon: Icons.timer_outlined,
            text: 'Timer defaults, feedback and appearance',
          ),
          _SummaryLine(
            icon: Icons.history,
            text:
                '$count focus ${count == 1 ? 'session' : 'sessions'}, '
                'including labels and notes',
          ),
          const SizedBox(height: 2),
          CheckboxListTile(
            key: PortableBackupExportDialog.includePresetsKey,
            value: include,
            onChanged: _presetsAvailable
                ? (value) =>
                      setState(() => _includePresets = value ?? false)
                : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Include saved presets'),
            subtitle: Text(_presetSubtitle),
          ),
          const SizedBox(height: 4),
          const _SummaryLine(
            icon: Icons.photo_library_outlined,
            text: 'Wallpaper photos and companion packs are never transferred.',
          ),
          const _SummaryLine(
            icon: Icons.timer_off_outlined,
            text: 'Active timers, one-off plans and laps are not included.',
          ),
          const SizedBox(height: 2),
          _SummaryNote(
            include
                ? 'Saving does not change local data. A later restore replaces '
                      'saved presets.'
                : 'Saving does not change local data. Saved presets stay on '
                      'this device.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: PortableBackupExportDialog.confirmKey,
          onPressed: () => Navigator.pop(
            context,
            PortableBackupExportChoice(includePresets: include),
          ),
          child: const Text('Save file'),
        ),
      ],
    );
  }
}

/// Shows the replacement preview for a validated backup and runs [onReplace].
///
/// The caller decodes the picked file first and passes the resulting
/// [DataBackup]. Returns true when the replacement succeeded and null when the
/// user cancels. A failed replacement keeps the dialog open with its error so
/// the user can retry or cancel; local data is only touched by [onReplace].
Future<bool?> showPortableBackupImportDialog(
  BuildContext context, {
  required DataBackup backup,
  required Future<void> Function(DataBackup) onReplace,
  String failureMessage = 'Could not restore the backup. Try again.',
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) => PortableBackupImportDialog(
      backup: backup,
      onReplace: onReplace,
      failureMessage: failureMessage,
    ),
  );
}

/// Replacement preview for a picked portable backup.
///
/// The modal stays pending while [onReplace] runs, closes on success and stays
/// open with an inline error when the replacement fails, so a failure can be
/// retried or cancelled instead of looking like a completed restore.
class PortableBackupImportDialog extends StatefulWidget {
  const PortableBackupImportDialog({
    required this.backup,
    required this.onReplace,
    this.failureMessage = 'Could not restore the backup. Try again.',
    super.key,
  });

  final DataBackup backup;
  final Future<void> Function(DataBackup) onReplace;
  final String failureMessage;

  static const cancelKey = ValueKey<String>('portable-backup-cancel');
  static const confirmKey = ValueKey<String>('portable-backup-restore');

  @override
  State<PortableBackupImportDialog> createState() =>
      _PortableBackupImportDialogState();
}

class _PortableBackupImportDialogState
    extends State<PortableBackupImportDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _replace() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onReplace(widget.backup);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FormatException catch (error) {
      _fail(error.message.isEmpty ? widget.failureMessage : error.message);
    } on StateError {
      // A backup backend can fail with a StateError, which is an Error rather
      // than an Exception. Retry and Cancel must stay available, so this
      // recoverable failure uses the safe caller message instead of leaving
      // the modal stuck pending.
      _fail(widget.failureMessage);
    } on Exception {
      _fail(widget.failureMessage);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope<bool>(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Restore backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('This file will replace your local data:'),
            const SizedBox(height: 10),
            PortableBackupSummary(backup: widget.backup),
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              _InlineError(error),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: PortableBackupImportDialog.cancelKey,
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: PortableBackupImportDialog.confirmKey,
            onPressed: _busy ? null : _replace,
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Restoring…'),
                    ],
                  )
                : const Text('Restore backup'),
          ),
        ],
      ),
    );
  }
}

/// Describes what a backup carries, for restore previews and legacy paste.
///
/// It names the preset sections and their counts when [DataBackup.focusPresets]
/// or [DataBackup.clockPresets] are present, and says omitted presets stay on
/// this device. Photos and companion packs are never transferred. Active
/// timers, one-off plans and laps are cleared by a replacement. When
/// [willReplace] is false (a copy or a file save) the closing line states that
/// local data is unchanged.
class PortableBackupSummary extends StatelessWidget {
  const PortableBackupSummary({
    required this.backup,
    this.willReplace = true,
    this.note,
    super.key,
  });

  final DataBackup backup;

  /// Whether the summary previews a replacement or only a review.
  final bool willReplace;

  /// An optional caller note, for example the copy-text privacy reminder.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final settings = backup.settings;
    final count = backup.sessions.length;
    final focusPresets = backup.focusPresets;
    final clockPresets = backup.clockPresets;

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
        if (focusPresets != null)
          _SummaryLine(
            icon: Icons.bookmarks_outlined,
            text: 'Saved Focus presets: ${focusPresets.presets.length}',
          )
        else if (clockPresets != null)
          const _SummaryLine(
            icon: Icons.bookmarks_outlined,
            text: 'Saved Focus presets stay on this device.',
          ),
        if (clockPresets != null)
          _SummaryLine(
            icon: Icons.bookmarks_outlined,
            text: 'Saved Clock presets: ${clockPresets.presets.length}',
          )
        else if (focusPresets != null)
          const _SummaryLine(
            icon: Icons.bookmarks_outlined,
            text: 'Saved Clock presets stay on this device.',
          ),
        if (focusPresets == null && clockPresets == null)
          const _SummaryLine(
            icon: Icons.bookmarks_outlined,
            text: 'Saved Focus and Clock presets stay on this device.',
          ),
        const _SummaryLine(
          icon: Icons.photo_library_outlined,
          text: 'Wallpaper photos and companion packs are never transferred.',
        ),
        _SummaryLine(
          icon: Icons.timer_off_outlined,
          text: willReplace
              ? 'Active timers, one-off plans and laps are cleared.'
              : 'Active timers, one-off plans and laps are not included.',
        ),
        const SizedBox(height: 2),
        _SummaryNote(
          willReplace
              ? 'Nothing changes until you confirm.'
              : 'Review only; local data is not changed.',
        ),
        if (note case final custom?) ...[
          const SizedBox(height: 6),
          _SummaryNote(custom),
        ],
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

class _SummaryNote extends StatelessWidget {
  const _SummaryNote(this.text);

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

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: colors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ),
      ],
    );
  }
}

String _presetWord(int count) => count == 1 ? 'preset' : 'presets';

String _themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

String _onOff(bool value) => value ? 'on' : 'off';
