import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/branding.dart';
import '../../core/storage/backup_file_transport.dart';
import '../../core/storage/data_backup.dart';
import '../../design/appearance_preferences.dart';
import '../focus/ambience/ambience.dart';
import '../focus/background/focus_wallpaper.dart';
import 'app_settings.dart';
import 'focus_ambience_page.dart';
import 'home_cards_page.dart';
import 'portable_backup_dialogs.dart';
import 'theme_colors_page.dart';
import 'wallpaper_page.dart';

/// Host answer for a Settings alert preview.
///
/// [ok] is false when the request reached the host but could not be honoured,
/// so the page can re-check the Android permission state. [message] is the
/// user-facing result and never contains a private path.
typedef SettingsAlertPreview = Future<({bool ok, String message})> Function({
  required bool sound,
  required bool vibration,
});

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.onSave,
    required this.onExport,
    required this.onReplace,
    required this.onClear,
    this.notificationsAvailable = false,
    this.checkNotificationPermission,
    this.requestNotificationPermission,
    this.checkExactAlarmPermission,
    this.onRequestExactAlarmPermission,
    this.onOpenNotificationSettings,
    this.onSendTestAlert,
    this.onPreviewCompletionChime,
    this.alertNotice,
    this.readPresetCounts,
    this.onBuildBackup,
    this.fileTransport,
    this.animationLab,
    this.developmentPacks,
    this.wallpaperSelection,
    this.wallpaperLocation = WallpaperLocation.both,
    this.onApplyWallpaper,
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
  /// Saving still owns the user's intent; this only reports existing state so
  /// the page never claims a permission it cannot verify.
  final Future<bool> Function()? checkNotificationPermission;

  /// Requests the Android notification permission.
  ///
  /// Only the contextual opt-in below calls this. A generic save never asks.
  final Future<bool> Function()? requestNotificationPermission;

  /// Reports whether exact alarms may be used on this device.
  final Future<bool> Function()? checkExactAlarmPermission;

  /// Opens the system exact-alarm grant page.
  final Future<bool> Function()? onRequestExactAlarmPermission;

  /// Opens this app's notification settings page.
  final Future<bool> Function()? onOpenNotificationSettings;

  /// Posts a real test notification on the completion channel.
  final SettingsAlertPreview? onSendTestAlert;

  /// Plays the real completion chime through the native host.
  final SettingsAlertPreview? onPreviewCompletionChime;

  /// The host's report of the last blocked, inexact or failed alert.
  final ValueListenable<String?>? alertNotice;

  /// Counts the saved presets a file save could include, or null when unknown.
  final Future<({int focus, int clock})?> Function()? readPresetCounts;

  /// Builds the exact backup document a file save writes.
  final Future<DataBackup> Function({required bool includePresets})?
  onBuildBackup;

  /// File transport for saving and restoring a backup document.
  ///
  /// Null hides the file actions and keeps the copy/paste fallback only.
  final BackupFileTransport? fileTransport;

  final WidgetBuilder? animationLab;
  final WidgetBuilder? developmentPacks;

  /// The saved wallpaper source when the host owns the photo store.
  ///
  /// Null falls back to the built-in choice in [AppSettings.appearance]; this
  /// page never reads local photo bytes itself.
  final WallpaperSelection? wallpaperSelection;

  /// Where the saved wallpaper appears, from the same stored choice.
  final WallpaperLocation wallpaperLocation;

  /// Commits a wallpaper draft. Null saves only the built-in choice through
  /// [onSave]; a host that stores the local photo supplies this instead.
  final Future<void> Function(WallpaperDraft draft)? onApplyWallpaper;

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
  bool? _exactAlarmsAllowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.notificationsAvailable) {
      unawaited(_refreshAlertPermissions());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from Android settings re-reads the real state instead of
    // trusting the value from before the user left.
    if (state == AppLifecycleState.resumed && widget.notificationsAvailable) {
      unawaited(_refreshAlertPermissions());
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notificationsAvailable &&
        (oldWidget.notificationsAvailable != widget.notificationsAvailable ||
            oldWidget.checkNotificationPermission !=
                widget.checkNotificationPermission ||
            oldWidget.checkExactAlarmPermission !=
                widget.checkExactAlarmPermission)) {
      unawaited(_refreshAlertPermissions());
    }
  }

  Future<void> _refreshAlertPermissions() async {
    await _refreshNotificationPermission();
    final check = widget.checkExactAlarmPermission;
    if (check == null) return;
    bool? allowed;
    try {
      allowed = await check();
    } catch (_) {
      allowed = null;
    }
    if (mounted) setState(() => _exactAlarmsAllowed = allowed);
  }

  Future<void> _refreshNotificationPermission() async {
    final check = widget.checkNotificationPermission;
    if (check == null) return;
    bool? allowed;
    try {
      allowed = await check();
    } catch (_) {
      allowed = null;
    }
    if (mounted) setState(() => _notificationsAllowed = allowed);
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
      await _refreshAlertPermissions();
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

  /// Applies the user's completion-alert intent.
  ///
  /// Turning alerts on is the one direct opt-in: it shows a short explainer and
  /// asks Android only if the user continues. `Not now` persists the off choice
  /// and leaves every timer working. Turning alerts off never prompts.
  Future<void> _toggleNotifications(AppSettings settings, bool value) async {
    if (!value) {
      await _save(settings.copyWith(notifications: false));
      return;
    }
    final check = widget.checkNotificationPermission;
    var allowed = _notificationsAllowed;
    if (allowed != true && check != null) {
      try {
        allowed = await check();
      } catch (_) {
        allowed = null;
      }
      if (mounted) setState(() => _notificationsAllowed = allowed);
    }
    if (!mounted) return;
    if (allowed == true) {
      await _save(settings.copyWith(notifications: true));
      return;
    }
    final request = widget.requestNotificationPermission;
    if (request == null) {
      // No permission bridge on this runner: keep the explicit intent.
      await _save(settings.copyWith(notifications: true));
      return;
    }

    final choice = await showDialog<_NotificationChoice>(
      context: context,
      builder: (context) => _NotificationPermissionDialog(
        askedBefore: settings.notificationPromptSeen,
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _NotificationChoice.notNow) {
      await _save(settings.copyWith(
        notifications: false,
        notificationPromptSeen: true,
      ));
      _message('Alerts stay off. Timers keep working.');
      return;
    }

    var granted = false;
    try {
      granted = await request();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    // The stored value is the user's intent. Android may still deny the
    // permission; the blocked state and its recovery row report that honestly.
    await _save(settings.copyWith(
      notifications: true,
      notificationPromptSeen: true,
    ));
    if (!mounted) return;
    if (granted) {
      _message('Completion alerts are on.');
    } else {
      _message('Alerts need notification access in Android settings.');
      await _refreshAlertPermissions();
    }
  }

  Future<void> _openNotificationSettings() async {
    final open = widget.onOpenNotificationSettings;
    if (open == null) return;
    try {
      final opened = await open();
      if (!mounted) return;
      if (!opened) _message('Android notification settings did not open.');
    } catch (_) {
      if (mounted) _message('Android notification settings did not open.');
    }
  }

  Future<void> _requestExactAlarms() async {
    final request = widget.onRequestExactAlarmPermission;
    if (request == null) return;
    var granted = false;
    try {
      granted = await request();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    if (!granted) {
      _message('Exact-alarm access stays off. Alerts may arrive late.');
    }
    await _refreshAlertPermissions();
  }

  Future<void> _sendTestAlert(AppSettings settings) async {
    final send = widget.onSendTestAlert;
    if (send == null) return;
    await _run(
      () async {
        final ({bool ok, String message}) result;
        try {
          result = await send(
            sound: settings.sound,
            vibration: settings.completionVibration,
          );
        } on Exception {
          throw const FormatException('Could not send the test alert.');
        }
        if (!mounted) return;
        _message(result.message);
        if (!result.ok) await _refreshAlertPermissions();
      },
      failure: 'Could not send the test alert. Try again.',
    );
  }

  Future<void> _previewCompletionChime(AppSettings settings) async {
    final preview = widget.onPreviewCompletionChime;
    if (preview == null) return;
    await _run(
      () async {
        final ({bool ok, String message}) result;
        try {
          result = await preview(
            sound: settings.sound,
            vibration: settings.completionVibration,
          );
        } on Exception {
          throw const FormatException('Could not play the completion chime.');
        }
        if (!mounted) return;
        _message(result.message);
      },
      failure: 'Could not play the completion chime. Try again.',
    );
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
                PortableBackupSummary(
                  backup: backup,
                  willReplace: false,
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

  bool get _fileBackupAvailable =>
      widget.onBuildBackup != null &&
      widget.fileTransport != null &&
      BackupFileTransport.isSupported;

  Future<({int focus, int clock})?> _readPresetCounts() async {
    final read = widget.readPresetCounts;
    if (read == null) return null;
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  /// Saves a backup file with the saved presets as a default-off opt-in.
  Future<void> _saveBackupFile() async {
    final build = widget.onBuildBackup;
    final transport = widget.fileTransport;
    if (build == null || transport == null || !_fileBackupAvailable) return;
    await _run(
      () async {
        final preview = await build(includePresets: false);
        if (!mounted) return;
        final counts = await _readPresetCounts();
        if (!mounted) return;
        final choice = await showPortableBackupExportDialog(
          context,
          sessionCount: preview.sessions.length,
          focusPresetCount: counts?.focus,
          clockPresetCount: counts?.clock,
        );
        if (choice == null || !mounted) return;
        final backup = choice.includePresets
            ? await build(includePresets: true)
            : preview;
        final text = backup.encode();
        final saved = await _writeBackupFile(transport, text);
        if (!mounted) return;
        // A cancelled save never reports success.
        _message(saved ? 'Backup saved.' : 'Backup not saved.');
      },
      failure: 'Could not save the backup file. Try again.',
    );
  }

  Future<bool> _writeBackupFile(
    BackupFileTransport transport,
    String text,
  ) async {
    try {
      return await transport.save(Uint8List.fromList(utf8.encode(text)));
    } on BackupFileException catch (error) {
      throw FormatException(error.message);
    }
  }

  /// Picks a file, decodes it with the same byte path as copy/paste, and shows
  /// the replacement preview before anything is committed.
  Future<void> _restoreFromFile() async {
    final transport = widget.fileTransport;
    if (transport == null || !_fileBackupAvailable) return;
    await _run(
      () async {
        final Uint8List? bytes;
        try {
          bytes = await transport.load();
        } on BackupFileException catch (error) {
          throw FormatException(error.message);
        }
        // An explicit cancellation changes nothing and reports nothing.
        if (bytes == null || !mounted) return;
        final backup = DataBackup.decodeBytes(bytes);
        if (!mounted) return;
        final restored = await showPortableBackupImportDialog(
          context,
          backup: backup,
          onReplace: widget.onReplace,
        );
        if (restored == true) _message('Backup restored.');
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

  /// Opens the theme editor. It merges against the newest stored settings when
  /// Apply runs, and a null platform seed keeps System on the grayscale chrome
  /// instead of inventing a hue.
  void _openThemeColors(AppSettings settings) {
    Navigator.of(context).push<void>(
      ThemeColorsPage.route(
        settings: settings,
        onSave: widget.onSave,
        latestSettings: () => widget.settings.value,
      ),
    );
  }

  /// Merges only the fields Home & Cards owns into the latest settings.
  ///
  /// The editor treats a thrown error as a failed save, so this awaits the real
  /// store instead of the page's own error-reporting wrapper.
  Future<void> _applyHomeCards(AppearancePreferences draft) async {
    final latest = widget.settings.value;
    await widget.onSave(
      latest.copyWith(
        appearance: latest.appearance.copyWith(
          homeLayout: draft.homeLayout,
          cardStyle: draft.cardStyle,
          cardEffect: draft.cardEffect,
          watchDial: draft.watchDial,
        ),
      ),
    );
  }

  void _openHomeCards(AppSettings settings) => _open(
    (_) => HomeCardsPage(
      appearance: settings.appearance,
      onApply: _applyHomeCards,
      lowPower: settings.lowPower,
      // Read the newest stored settings when the wallpaper opens, so a save
      // made while this editor was open is not replaced by a stale copy.
      onOpenWallpaper: () => _openWallpaper(widget.settings.value),
    ),
  );

  void _openWallpaper(AppSettings settings) {
    final selection =
        widget.wallpaperSelection ??
        WallpaperSelection.fromAppearance(settings.appearance.wallpaper);
    _open(
      (_) => WallpaperPage(
        selection: selection,
        location: widget.wallpaperLocation,
        onApply: widget.onApplyWallpaper ?? _saveWallpaperChoice,
        reducedMotion: settings.reducedMotion,
        lowPower: settings.lowPower,
      ),
    );
  }

  /// Saves only the built-in wallpaper choice when no photo store is wired.
  ///
  /// The wallpaper editor keeps itself open when this throws, so the failure is
  /// not swallowed here.
  Future<void> _saveWallpaperChoice(WallpaperDraft draft) async {
    final latest = widget.settings.value;
    await widget.onSave(
      latest.copyWith(
        appearance: latest.appearance.copyWith(
          wallpaper: draft.appearanceType,
        ),
      ),
    );
  }

  void _openFocusAmbience(AppSettings settings) {
    Navigator.of(context).push<void>(
      FocusAmbiencePage.route(
        preferences: settings.focusAmbience,
        onSave: _saveFocusAmbience,
      ),
    );
  }

  /// Saves ambience into the newest settings so it never overwrites another
  /// editor's change, and leaves Sound, notifications and haptics untouched.
  Future<void> _saveFocusAmbience(FocusAmbiencePreferences next) async {
    final latest = widget.settings.value;
    await widget.onSave(latest.copyWith(focusAmbience: next));
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
                            : (value) =>
                                  _toggleNotifications(settings, value),
                      ),
                      _SwitchRow(
                        title: 'Completion vibration',
                        subtitle:
                            'Vibrate when a timer finishes. Separate from '
                            'touch haptics.',
                        value: settings.completionVibration,
                        onChanged: _busy
                            ? null
                            : (value) => _save(
                                settings.copyWith(completionVibration: value),
                              ),
                      ),
                      if (settings.notifications &&
                          _notificationsAllowed == false)
                        _SettingsRow(
                          icon: Icons.open_in_new,
                          title: 'Open notification settings',
                          subtitle:
                              'Allow MinuteMeadow alerts in Android settings.',
                          enabled: !_busy,
                          onTap: _busy ? null : _openNotificationSettings,
                        ),
                      if (settings.notifications &&
                          _exactAlarmsAllowed == false)
                        _SettingsRow(
                          icon: Icons.alarm,
                          title: 'Allow exact alarms',
                          subtitle:
                              'Without this, alerts may arrive a little late.',
                          enabled: !_busy,
                          onTap: _busy ? null : _requestExactAlarms,
                        ),
                      if (widget.onSendTestAlert != null)
                        _SettingsRow(
                          icon: Icons.notification_add_outlined,
                          title: 'Send test alert',
                          subtitle:
                              'Post a notification like a finished timer.',
                          enabled: !_busy,
                          onTap: _busy
                              ? null
                              : () => _sendTestAlert(settings),
                        ),
                      if (widget.onPreviewCompletionChime != null)
                        _SettingsRow(
                          icon: Icons.music_note,
                          title: 'Preview completion chime',
                          subtitle: 'Play the sound a finished timer makes.',
                          enabled: !_busy,
                          onTap: _busy
                              ? null
                              : () => _previewCompletionChime(settings),
                        ),
                    ],
                  ),
                  if (widget.alertNotice case final notice?)
                    ValueListenableBuilder<String?>(
                      valueListenable: notice,
                      builder: (context, text, _) => text == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _AlertNotice(text),
                            ),
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
                      subtitle: 'Touch vibration for controls.',
                      value: settings.haptics,
                      onChanged: _busy
                          ? null
                          : (value) => _save(settings.copyWith(haptics: value)),
                    ),
                    if (FocusAmbiencePlayer.isSupported)
                      _SettingsRow(
                        icon: Icons.graphic_eq,
                        title: 'Focus ambience',
                        subtitle:
                            'Optional quiet sound while a focus session runs.',
                        value: settings.focusAmbience.track.label,
                        enabled: !_busy,
                        onTap: _busy
                            ? null
                            : () => _openFocusAmbience(settings),
                      ),
                  ],
                ),
                const _SectionHeader('Appearance', Icons.palette_outlined),
                _SettingsGroup(
                  children: [
                    _SettingsRow(
                      icon: Icons.palette_outlined,
                      title: 'Theme & Colors',
                      subtitle: 'Palette, fonts, dark mode and AMOLED.',
                      enabled: !_busy,
                      onTap: _busy ? null : () => _openThemeColors(settings),
                    ),
                    _SettingsRow(
                      icon: Icons.space_dashboard_outlined,
                      title: 'Home & Cards',
                      subtitle: 'Home layout, card style, motion and wallpaper.',
                      enabled: !_busy,
                      onTap: _busy ? null : () => _openHomeCards(settings),
                    ),
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
                      subtitle: 'Replace local data from pasted text.',
                      enabled: !_busy,
                      onTap: _busy ? null : _import,
                    ),
                    if (_fileBackupAvailable) ...[
                      _SettingsRow(
                        icon: Icons.save_alt,
                        title: 'Save backup file',
                        subtitle:
                            'Write a backup file. Saved presets are optional.',
                        enabled: !_busy,
                        onTap: _busy ? null : _saveBackupFile,
                      ),
                      _SettingsRow(
                        icon: Icons.folder_open,
                        title: 'Restore from file',
                        subtitle: 'Choose a backup file and preview it first.',
                        enabled: !_busy,
                        onTap: _busy ? null : _restoreFromFile,
                      ),
                    ],
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
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      title: 'Licenses',
                      subtitle: 'Open-source notices and attributions.',
                      enabled: !_busy,
                      onTap: _busy
                          ? null
                          : () => _open(
                              (_) => LicensePage(
                                applicationName: Branding.name,
                                applicationVersion: Branding.displayVersion,
                              ),
                            ),
                    ),
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

enum _NotificationChoice { notNow, allow }

/// Contextual explainer shown before the Android permission request.
///
/// It is only reachable from a direct opt-in. `Not now` dismisses without
/// changing any timer and the caller persists that choice.
class _NotificationPermissionDialog extends StatelessWidget {
  const _NotificationPermissionDialog({required this.askedBefore});

  final bool askedBefore;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Turn on completion alerts?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'MinuteMeadow can alert you when a timer ends, even while the app '
            'is closed. Android will ask for notification access next.',
          ),
          if (askedBefore) ...[
            const SizedBox(height: 10),
            const Text(
              'Alerts stayed off last time. Timers keep working either way.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, _NotificationChoice.notNow),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _NotificationChoice.allow),
          child: const Text('Allow alerts'),
        ),
      ],
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

class _AlertNotice extends StatelessWidget {
  const _AlertNotice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
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
            PortableBackupSummary(
              backup: backup,
              willReplace: true,
              note: _pasteNote(backup),
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

/// Names the sections a pasted document preserves and replaces.
String _pasteNote(DataBackup backup) {
  final replacesPresets =
      backup.focusPresets != null || backup.clockPresets != null;
  return replacesPresets
      ? 'This also clears active timers and laps. The preset sections named '
            'above are replaced; omitted presets and installed companions stay '
            'on this device.'
      : 'This also clears active timers and laps. Saved Focus and Clock '
            'presets and installed companions stay on this device.';
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
          const _SummaryLine(
            icon: Icons.photo_library_outlined,
            text: 'The saved wallpaper photo is removed.',
          ),
          const SizedBox(height: 4),
          const _Note(
            'This cannot be undone. A backup preserves preferences and '
            'history only, not presets or companions, and it never contains '
            'the wallpaper photo.',
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
