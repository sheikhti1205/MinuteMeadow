import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'backup_file_transport_api.dart';
import 'backup_file_transport_web_stub.dart'
    if (dart.library.js_interop) 'backup_file_transport_web.dart' as web;

export 'backup_file_transport_api.dart';

/// Bytes-only file transport for approved portable backups.
///
/// The transport saves a fixed public file name and returns the bytes of one
/// picked document. It never parses, merges or persists a backup: the caller
/// decodes the returned bytes with `DataBackup.decodeBytes` and keeps the
/// copy/paste fallback.
///
/// On Android the bytes cross `app.companionfocus/backup_documents` to the
/// Storage Access Framework, so no broad storage permission is requested and no
/// private path reaches Dart. On web a save is a normal browser download and a
/// pick is the browser file picker. Other runners report
/// [BackupFileError.unavailable].
///
/// Cancellation is explicit: [save] returns false and [load] returns null.
/// A read or write problem throws [BackupFileException] instead.
final class BackupFileTransport {
  BackupFileTransport({BackupFileBackend? backend})
    : _backend = backend ?? _platformBackend();

  /// The transport for the current platform.
  static final BackupFileTransport instance = BackupFileTransport();

  /// The fixed cap, matching [maxBackupFileBytes].
  static const int maxBytes = maxBackupFileBytes;

  /// The fixed public file name, matching [backupFileName].
  static const String fileName = backupFileName;

  /// Whether this runner has a file transport for backups.
  static bool get isSupported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  final BackupFileBackend _backend;

  static BackupFileBackend _platformBackend() {
    if (kIsWeb) {
      final backend = web.createWebBackupFileBackend();
      if (backend != null) return backend;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidBackupFileBackend();
    }
    return const UnavailableBackupFileBackend();
  }

  /// Saves [bytes] as the fixed public backup name.
  ///
  /// Returns true when a file was written and false when the save was
  /// cancelled, including an engine that detached while the dialog was open.
  /// Throws [BackupFileException] for a failed save and [ArgumentError] when
  /// [bytes] is empty.
  ///
  /// On Android the chosen document is truncated when the provider opens it,
  /// so a save that fails or is abandoned after the user chose the destination
  /// cannot restore the previous contents.
  Future<bool> save(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'A backup cannot be empty.');
    }
    if (bytes.length > maxBytes) {
      throw BackupFileException(BackupFileError.tooLarge, size: bytes.length);
    }
    try {
      return await _backend.save(bytes, fileName);
    } on BackupFileException {
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') return false;
      throw _mapPlatformException(error, BackupFileError.writeFailed);
    } on MissingPluginException {
      throw const BackupFileException(BackupFileError.unavailable);
    } on Exception {
      throw const BackupFileException(BackupFileError.writeFailed);
    }
  }

  /// Reads one picked backup document.
  ///
  /// Returns null when the picker was cancelled. The returned bytes are capped
  /// at [maxBytes]; a larger document is never handed to the caller. Throws
  /// [BackupFileException] for a failed read.
  Future<Uint8List?> load() async {
    final Uint8List? bytes;
    try {
      bytes = await _backend.load();
    } on BackupFileException {
      rethrow;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') return null;
      throw _mapPlatformException(error, BackupFileError.readFailed);
    } on MissingPluginException {
      throw const BackupFileException(BackupFileError.unavailable);
    } on Exception {
      throw const BackupFileException(BackupFileError.readFailed);
    }
    if (bytes == null) return null;
    if (bytes.length > maxBytes) {
      throw BackupFileException(BackupFileError.tooLarge, size: bytes.length);
    }
    return bytes;
  }

  static BackupFileException _mapPlatformException(
    PlatformException error,
    BackupFileError fallback,
  ) {
    switch (error.code) {
      case 'too_large':
        return const BackupFileException(BackupFileError.tooLarge);
      case 'unsupported_type':
        return const BackupFileException(BackupFileError.unsupportedType);
      case 'busy':
        return const BackupFileException(BackupFileError.busy);
      default:
        return BackupFileException(fallback);
    }
  }
}

/// The Android bridge to `BackupDocuments`.
///
/// Byte arrays cross the method channel as `ByteArray` on the native side. The
/// native host returns true/false for a save, null for a cancelled pick and a
/// byte array for a picked document.
final class AndroidBackupFileBackend implements BackupFileBackend {
  const AndroidBackupFileBackend({
    this.channel = const MethodChannel(channelName),
  });

  static const String channelName = 'app.companionfocus/backup_documents';

  final MethodChannel channel;

  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    final saved = await channel.invokeMethod<bool>(
      'save',
      <String, Object>{'bytes': bytes, 'fileName': fileName},
    );
    return saved ?? false;
  }

  @override
  Future<Uint8List?> load() async {
    final value = await channel.invokeMethod<Object?>('pick');
    if (value == null) return null;
    if (value is Uint8List) return value;
    throw const BackupFileException(BackupFileError.readFailed);
  }
}

/// The fallback for runners without a backup file transport.
final class UnavailableBackupFileBackend implements BackupFileBackend {
  const UnavailableBackupFileBackend();

  @override
  Future<bool> save(Uint8List bytes, String fileName) async =>
      throw const BackupFileException(BackupFileError.unavailable);

  @override
  Future<Uint8List?> load() async =>
      throw const BackupFileException(BackupFileError.unavailable);
}
