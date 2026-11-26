import 'dart:convert';

import '../../features/settings/app_settings.dart';
import 'session_record.dart';

class DataBackup {
  const DataBackup({required this.settings, required this.sessions});

  final AppSettings settings;
  final List<SessionRecord> sessions;

  String encode() => jsonEncode({
    'schema': 1,
    'settings': settings.toJson(),
    'sessions': [for (final session in sessions) session.toJson()],
  });

  static DataBackup decode(String source) {
    if (source.length > 16 * 1024 * 1024) {
      throw const FormatException('The backup is too large.');
    }
    final Object? data = jsonDecode(source);
    if (data case {
      'schema': 1,
      'settings': final Object? settings,
      'sessions': final List<Object?> records,
    } when records.length <= 100000) {
      final sessions = records.map(SessionRecord.fromJson).toList();
      if (sessions.map((session) => session.id).toSet().length != sessions.length) {
        throw const FormatException('The backup contains duplicate sessions.');
      }
      return DataBackup(
        settings: AppSettings.fromJson(settings),
        sessions: sessions,
      );
    }
    throw const FormatException('Unsupported backup format.');
  }
}
