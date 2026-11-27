import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/time/timer_defaults.dart';
import '../../design/appearance_preferences.dart';
import '../focus/ambience/focus_ambience_preferences.dart';

class AppSettings {
  const AppSettings({
    this.focusMinutes = TimerDefaults.focusMinutes,
    this.shortBreakMinutes = TimerDefaults.shortBreakMinutes,
    this.longBreakMinutes = TimerDefaults.longBreakMinutes,
    this.themeMode = ThemeMode.system,
    this.notifications = false,
    this.sound = true,
    this.haptics = true,
    this.reducedMotion = false,
    this.lowPower = false,
    this.appearance = const AppearancePreferences(),
    this.completionVibration = true,
    this.notificationPromptSeen = false,
    this.focusAmbience = const FocusAmbiencePreferences(),
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final ThemeMode themeMode;
  final bool notifications;
  final bool sound;
  final bool haptics;
  final bool reducedMotion;
  final bool lowPower;

  /// Theme colours, fonts and home card choices shown by the appearance
  /// editors. Timer and alert settings stay on this object.
  final AppearancePreferences appearance;

  /// Vibration for timer completion, independent of touch haptics.
  final bool completionVibration;

  /// Whether the one-time notification prompt was already shown. Retained so
  /// the prompt is not repeated after a settings save or restore.
  final bool notificationPromptSeen;

  /// The optional Android Focus ambience. This is an ordinary portable
  /// preference: the track name and volume only, never generated audio, files
  /// or pack media.
  final FocusAmbiencePreferences focusAmbience;

  AppSettings copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    ThemeMode? themeMode,
    bool? notifications,
    bool? sound,
    bool? haptics,
    bool? reducedMotion,
    bool? lowPower,
    AppearancePreferences? appearance,
    bool? completionVibration,
    bool? notificationPromptSeen,
    FocusAmbiencePreferences? focusAmbience,
  }) => AppSettings(
    focusMinutes: focusMinutes ?? this.focusMinutes,
    shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
    longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
    themeMode: themeMode ?? this.themeMode,
    notifications: notifications ?? this.notifications,
    sound: sound ?? this.sound,
    haptics: haptics ?? this.haptics,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    lowPower: lowPower ?? this.lowPower,
    appearance: appearance ?? this.appearance,
    completionVibration: completionVibration ?? this.completionVibration,
    notificationPromptSeen:
        notificationPromptSeen ?? this.notificationPromptSeen,
    focusAmbience: focusAmbience ?? this.focusAmbience,
  );

  Map<String, Object> toJson() => {
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'theme': themeMode.name,
    'notifications': notifications,
    'sound': sound,
    'haptics': haptics,
    'reducedMotion': reducedMotion,
    'lowPower': lowPower,
    'appearance': appearance.toJson(),
    'completionVibration': completionVibration,
    'notificationPromptSeen': notificationPromptSeen,
    FocusAmbiencePreferences.settingsKey: focusAmbience.toMap(),
  };

  String encode() => jsonEncode({'schema': 1, ...toJson()});

  static AppSettings decode(String source) {
    final Object? json = jsonDecode(source);
    if (json case {'schema': final Object? version} when version != 1) {
      throw const FormatException('Unsupported settings version.');
    }
    return fromJson(json);
  }

  /// Reads the settings object used by local storage and schema 1 backups.
  ///
  /// The timer, feedback and theme keys keep their original validation.
  /// Appearance, completion vibration and the notification prompt are additive
  /// optional fields: an older document that omits them decodes to the original
  /// defaults, and unknown keys are ignored.
  static AppSettings fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Invalid settings.');
    }

    final focusMinutes = json['focusMinutes'];
    final shortBreakMinutes = json['shortBreakMinutes'];
    final longBreakMinutes = json['longBreakMinutes'];
    if (focusMinutes is! int ||
        shortBreakMinutes is! int ||
        longBreakMinutes is! int ||
        focusMinutes < 1 ||
        focusMinutes > 180 ||
        shortBreakMinutes < 1 ||
        shortBreakMinutes > 60 ||
        longBreakMinutes < 1 ||
        longBreakMinutes > 60) {
      throw const FormatException('Invalid settings.');
    }

    final theme = json['theme'];
    if (theme is! String) {
      throw const FormatException('Invalid theme.');
    }
    final themeMode = switch (theme) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => throw const FormatException('Invalid theme.'),
    };

    final notifications = _requiredBool(json, 'notifications');
    final sound = _requiredBool(json, 'sound');
    final haptics = _requiredBool(json, 'haptics');
    final reducedMotion = _requiredBool(json, 'reducedMotion');
    final lowPower = _requiredBool(json, 'lowPower');

    return AppSettings(
      focusMinutes: focusMinutes,
      shortBreakMinutes: shortBreakMinutes,
      longBreakMinutes: longBreakMinutes,
      themeMode: themeMode,
      notifications: notifications,
      sound: sound,
      haptics: haptics,
      reducedMotion: reducedMotion,
      lowPower: lowPower,
      appearance: AppearancePreferences.fromJson(json['appearance']),
      completionVibration: _optionalBool(json, 'completionVibration', true),
      notificationPromptSeen: _optionalBool(
        json,
        'notificationPromptSeen',
        false,
      ),
      focusAmbience: FocusAmbiencePreferences.fromMap(
        json[FocusAmbiencePreferences.settingsKey],
      ),
    );
  }
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw const FormatException('Invalid settings.');
}

bool _optionalBool(Map<String, Object?> json, String key, bool fallback) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is bool) return value;
  throw FormatException('Invalid $key.');
}
