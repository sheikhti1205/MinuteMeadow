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
    this.notificationsAvailable = false,
    super.key,
  });

  final ValueNotifier<AppSettings> settings;
  final Future<void> Function(AppSettings) onSave;
  final Future<String> Function() onExport;
  final Future<void> Function(DataBackup) onReplace;
  final bool notificationsAvailable;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FormatException catch (error) {
      _message(error.message);
    } on Exception {
      _message('Could not update local data. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

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
      await _run(() => widget.onSave(change(minutes)));
    }
  }

  Future<void> _export() => _run(() async {
    final backup = await widget.onExport();
    if (!mounted) return;
    final copy = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy backup'),
        content: const Text(
          'The backup contains preferences and focus history. '
          'Keep a copy somewhere private.',
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
    if (copy == true) {
      await Clipboard.setData(ClipboardData(text: backup));
      _message('Backup copied.');
    }
  });

  Future<void> _import() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _BackupDialog(),
    );
    if (text == null || !mounted) return;
    await _run(() async {
      final backup = DataBackup.decode(text);
      await widget.onReplace(backup);
      _message('Backup restored.');
    });
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear timer data?'),
        content: const Text(
          'This removes focus history and active timers and resets preferences.',
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
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() async {
        await widget.onReplace(const DataBackup(
          settings: AppSettings(),
          sessions: [],
        ));
        _message('Timer data cleared.');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: ValueListenableBuilder(
        valueListenable: widget.settings,
        builder: (context, settings, _) => ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const _Heading('Timer defaults'),
            ListTile(
              title: const Text('Focus duration'),
              subtitle: Text('${settings.focusMinutes} min'),
              enabled: !_busy,
              onTap: () => _duration('Focus duration', settings.focusMinutes, 180,
                (value) => settings.copyWith(focusMinutes: value)),
            ),
            ListTile(
              title: const Text('Short break'),
              subtitle: Text('${settings.shortBreakMinutes} min'),
              enabled: !_busy,
              onTap: () => _duration('Short break', settings.shortBreakMinutes, 60,
                (value) => settings.copyWith(shortBreakMinutes: value)),
            ),
            ListTile(
              title: const Text('Long break'),
              subtitle: Text('${settings.longBreakMinutes} min'),
              enabled: !_busy,
              onTap: () => _duration('Long break', settings.longBreakMinutes, 60,
                (value) => settings.copyWith(longBreakMinutes: value)),
            ),
            const Divider(),
            const _Heading('Feedback'),
            if (widget.notificationsAvailable)
              SwitchListTile(
                title: const Text('Completion notifications'),
                subtitle: const Text('Alerts when a timer ends, even outside the app.'),
                value: settings.notifications,
                onChanged: _busy ? null : (value) => _run(
                  () => widget.onSave(settings.copyWith(notifications: value)),
                ),
              ),
            SwitchListTile(
              title: const Text('Completion sound'),
              value: settings.sound,
              onChanged: _busy ? null : (value) => _run(
                () => widget.onSave(settings.copyWith(sound: value)),
              ),
            ),
            SwitchListTile(
              title: const Text('Haptic feedback'),
              value: settings.haptics,
              onChanged: _busy ? null : (value) => _run(
                () => widget.onSave(settings.copyWith(haptics: value)),
              ),
            ),
            const Divider(),
            const _Heading('Appearance'),
            ListTile(
              title: const Text('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                onChanged: _busy ? null : (value) {
                  if (value != null) {
                    _run(() => widget.onSave(settings.copyWith(themeMode: value)));
                  }
                },
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Reduce motion'),
              value: settings.reducedMotion,
              onChanged: _busy ? null : (value) => _run(
                () => widget.onSave(settings.copyWith(reducedMotion: value)),
              ),
            ),
            const Divider(),
            const _Heading('Local data'),
            ListTile(title: const Text('Export backup'), onTap: _busy ? null : _export),
            ListTile(title: const Text('Import backup'), onTap: _busy ? null : _import),
            ListTile(title: const Text('Clear timer data'), onTap: _busy ? null : _reset),
            const Divider(),
            const ListTile(
              title: Text(Branding.name),
              subtitle: Text('Version ${Branding.version}'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Minutes'),
        onFieldSubmitted: (_) => _submit(),
        validator: (text) {
          final value = int.tryParse(text?.trim() ?? '');
          return value == null || value < 1 || value > widget.limit
              ? 'Enter 1 to ${widget.limit} minutes.'
              : null;
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

class _BackupDialog extends StatefulWidget {
  const _BackupDialog();

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Restore backup'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('This replaces preferences, active timers and focus history.'),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Backup text'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Replace data'),
      ),
    ],
  );
}
