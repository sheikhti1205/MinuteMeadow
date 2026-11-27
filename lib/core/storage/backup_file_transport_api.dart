import 'dart:typed_data';

/// The fixed byte cap for one portable backup document: 16 MiB.
///
/// The transport enforces this before a save, before reading a pick on web and
/// again on the bytes it returns, so a document cannot grow past the same
/// budget `DataBackup.maxBytes` uses for decoding.
const int maxBackupFileBytes = 16 * 1024 * 1024;

/// The public file name offered to a save dialog or browser download.
///
/// It is a fixed product name, never a device path.
const String backupFileName = 'minutemeadow-backup.json';

/// Why a backup file could not be transported.
enum BackupFileError {
  /// The bytes exceed [maxBackupFileBytes].
  tooLarge,

  /// The picked document is clearly not a JSON backup.
  unsupportedType,

  /// The document could not be opened or read.
  readFailed,

  /// The destination could not be written.
  writeFailed,

  /// This runner has no file transport.
  unavailable,

  /// Another picker or save dialog is still open.
  busy,
}

/// A transport failure with a user-safe [message] and no private path.
final class BackupFileException implements Exception {
  const BackupFileException(this.error, {this.size});

  final BackupFileError error;

  /// The rejected size in bytes, when the failure was a size limit.
  final int? size;

  String get message {
    switch (error) {
      case BackupFileError.tooLarge:
        return 'The backup is too large. The limit is 16 MiB.';
      case BackupFileError.unsupportedType:
        return 'That file is not a backup.';
      case BackupFileError.readFailed:
        return 'Could not read the backup file.';
      case BackupFileError.writeFailed:
        return 'Could not save the backup file.';
      case BackupFileError.unavailable:
        return 'File backups are not available here.';
      case BackupFileError.busy:
        return 'Another file request is already open.';
    }
  }

  @override
  String toString() =>
      'BackupFileException(${error.name}${size == null ? '' : ', $size bytes'})';
}

/// The platform operations behind `BackupFileTransport`.
///
/// Implementations move bytes only. They never parse a document, never persist
/// timer or preset state and never expose a picked path to the caller.
abstract interface class BackupFileBackend {
  /// Writes [bytes] under [fileName].
  ///
  /// Returns true when the document was written and false when the save was
  /// cancelled, including platform teardown. Failures are thrown.
  Future<bool> save(Uint8List bytes, String fileName);

  /// Reads one picked document.
  ///
  /// Returns null when the user cancelled the picker. Failures are thrown.
  Future<Uint8List?> load();
}
