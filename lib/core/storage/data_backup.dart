import 'dart:convert';

import '../../features/settings/app_settings.dart';
import 'backup_presets.dart';
import 'session_record.dart';

export 'backup_presets.dart';

/// A portable snapshot of the data MinuteMeadow can restore.
///
/// Schema 1 keeps the original settings and history document. Schema 2 is
/// opt-in: it adds the scoped Focus and Clock preset documents and names the
/// sections it carries in `scope`. Constructing a backup with preset documents
/// (or with [DataBackup.portable]) writes schema 2; the ordinary constructor
/// still writes schema 1, so existing backups and callers are unchanged.
///
/// A schema 2 document rejects anything that is not part of its scope. Settings
/// and history are always present; the Focus and Clock preset documents are
/// optional sections. Active timers, one-off plans, checkpoint envelopes,
/// companion packs and media are not backup data and must never be smuggled in
/// as extra sections.
class DataBackup {
  const DataBackup({
    required this.settings,
    required this.sessions,
    this.focusPresets,
    this.clockPresets,
  }) : _portable = false;

  /// Creates a schema 2 backup even when it carries only settings and history.
  const DataBackup.portable({
    required this.settings,
    required this.sessions,
    this.focusPresets,
    this.clockPresets,
  }) : _portable = true;

  static const maxBytes = 16 * 1024 * 1024;
  static const maxSessions = 100000;

  /// The application marker written into schema 2 documents.
  static const appName = 'minutemeadow';

  static const _sections = <String>{
    'settings',
    'sessions',
    'focusPresets',
    'clockPresets',
  };

  final AppSettings settings;
  final List<SessionRecord> sessions;

  /// The Focus presets to restore, or null when the backup does not carry them.
  final FocusPresetsDocument? focusPresets;

  /// The Clock presets to restore, or null when the backup does not carry them.
  final ClockPresetsDocument? clockPresets;

  final bool _portable;

  /// Whether this backup writes the schema 2 document.
  bool get isPortable =>
      _portable || focusPresets != null || clockPresets != null;

  int get schemaVersion => isPortable ? 2 : 1;

  /// The data sections this backup carries.
  Set<String> get scope => <String>{
    'settings',
    'sessions',
    if (focusPresets != null) 'focusPresets',
    if (clockPresets != null) 'clockPresets',
  };

  /// Writes the backup text.
  ///
  /// Throws a [FormatException] when the document cannot be written within
  /// [maxBytes], so an export fails with a message instead of producing a file
  /// the restore path would have to reject.
  String encode() {
    focusPresets?.validate();
    clockPresets?.validate();
    final encoded = jsonEncode(
      isPortable ? _portableDocument() : _legacyDocument(),
    );
    if (utf8.encode(encoded).length > maxBytes) {
      throw const FormatException('The backup is too large to export.');
    }
    return encoded;
  }

  Map<String, Object?> _legacyDocument() => <String, Object?>{
    'schema': 1,
    'settings': settings.toJson(),
    'sessions': <Object?>[for (final session in sessions) session.toJson()],
  };

  Map<String, Object?> _portableDocument() => <String, Object?>{
    'schema': 2,
    'app': appName,
    'scope': <String>[
      'settings',
      'sessions',
      if (focusPresets != null) 'focusPresets',
      if (clockPresets != null) 'clockPresets',
    ],
    'settings': settings.toJson(),
    'sessions': <Object?>[for (final session in sessions) session.toJson()],
    if (focusPresets case final document?) 'focusPresets': document.toJson(),
    if (clockPresets case final document?) 'clockPresets': document.toJson(),
  };

  /// Reads a backup from normalized text.
  ///
  /// A UTF-8 byte-order mark and surrounding whitespace are ignored. The size
  /// limit is enforced as UTF-8 bytes, so a document cannot expand past the
  /// same budget when written to a file.
  static DataBackup decode(String source) {
    if (source.length > maxBytes) {
      throw const FormatException('The backup is too large.');
    }
    return decodeBytes(utf8.encode(_normalize(source)));
  }

  /// Reads a UTF-8 backup from bytes.
  ///
  /// The byte entry enforces the size limit before decoding and rejects
  /// malformed UTF-8 instead of replacing it, then follows the same strict
  /// text path as [decode].
  static DataBackup decodeBytes(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('The backup is too large.');
    }
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xff) {
        throw const FormatException('The backup is not valid UTF-8.');
      }
    }
    final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException('The backup is not valid UTF-8.');
    }
    return _decodeText(_normalize(source));
  }

  static DataBackup _decodeText(String source) {
    final Object? data;
    try {
      data = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Unsupported backup format.');
    }
    if (data case {
      'schema': 1,
      'settings': final Object? settings,
      'sessions': final List<Object?> records,
    } when records.length <= maxSessions) {
      final sessions = records
          .map(SessionRecord.fromJson)
          .toList(growable: false);
      if (sessions.map((session) => session.id).toSet().length !=
          sessions.length) {
        throw const FormatException('The backup contains duplicate sessions.');
      }
      return DataBackup(
        settings: AppSettings.fromJson(settings),
        sessions: sessions,
      );
    }
    if (data is Map<String, Object?>) {
      final version = data['schema'];
      if (version is int && version == 2) {
        return _decodeSchema2(data);
      }
    }
    throw const FormatException('Unsupported backup format.');
  }

  static DataBackup _decodeSchema2(Map<String, Object?> data) {
    if (data['app'] != appName) {
      throw const FormatException('Unsupported backup format.');
    }
    final rawScope = data['scope'];
    if (rawScope is! List<Object?>) {
      throw const FormatException('The backup scope is invalid.');
    }
    final declared = <String>{};
    for (final entry in rawScope) {
      if (entry is! String ||
          !_sections.contains(entry) ||
          !declared.add(entry)) {
        throw const FormatException('The backup scope is invalid.');
      }
    }
    const reserved = <String>{'schema', 'app', 'scope'};
    final present = <String>{
      for (final key in data.keys)
        if (!reserved.contains(key)) key,
    };
    if (!_sameSet(declared, present)) {
      throw const FormatException(
        'The backup scope does not match its sections.',
      );
    }
    if (!declared.contains('settings') || !declared.contains('sessions')) {
      throw const FormatException('The backup is missing settings or history.');
    }

    final rawSessions = data['sessions'];
    if (rawSessions is! List<Object?> || rawSessions.length > maxSessions) {
      throw const FormatException('Invalid focus history.');
    }
    final sessions = rawSessions
        .map(SessionRecord.fromJson)
        .toList(growable: false);
    if (sessions.map((session) => session.id).toSet().length !=
        sessions.length) {
      throw const FormatException('The backup contains duplicate sessions.');
    }

    final focusPresets = declared.contains('focusPresets')
        ? FocusPresetsDocument.decode(data['focusPresets'])
        : null;
    final clockPresets = declared.contains('clockPresets')
        ? ClockPresetsDocument.decode(data['clockPresets'])
        : null;
    return DataBackup.portable(
      settings: AppSettings.fromJson(data['settings']),
      sessions: sessions,
      focusPresets: focusPresets,
      clockPresets: clockPresets,
    );
  }
}

String _normalize(String source) {
  var value = source.trim();
  if (value.startsWith('\uFEFF')) {
    value = value.substring(1).trimLeft();
  }
  return value;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
