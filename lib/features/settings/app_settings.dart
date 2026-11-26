import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/time/timer_defaults.dart';

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
  };

  String encode() => jsonEncode({'schema': 1, ...toJson()});

  static AppSettings decode(String source) {
    final Object? json = jsonDecode(source);
    if (json case {'schema': final Object? version} when version != 1) {
      throw const FormatException('Unsupported settings version.');
    }
    return fromJson(json);
  }

  static AppSettings fromJson(Object? json) {
    if (json case {
      'focusMinutes': final int focusMinutes,
      'shortBreakMinutes': final int shortBreakMinutes,
      'longBreakMinutes': final int longBreakMinutes,
      'theme': final String theme,
      'notifications': final bool notifications,
      'sound': final bool sound,
      'haptics': final bool haptics,
      'reducedMotion': final bool reducedMotion,
      'lowPower': final bool lowPower,
    } when focusMinutes >= 1 &&
        focusMinutes <= 180 &&
        shortBreakMinutes >= 1 &&
        shortBreakMinutes <= 60 &&
        longBreakMinutes >= 1 &&
        longBreakMinutes <= 60) {
      final themeMode = switch (theme) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => throw const FormatException('Invalid theme.'),
      };
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
      );
    }
    throw const FormatException('Invalid settings.');
  }
}
