import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'backup_file_transport_api.dart';

/// Browser file transport for portable backups.
///
/// A save is a normal browser download of an in-memory JSON file and a pick is
/// the browser file picker, so the page never needs a writable path. The
/// document is size-checked before it is read and again after, keeping the same
/// 16 MiB cap as the native transport. A browser download has no cancellation
/// signal, so a started save reports true.
final class WebBackupFileBackend implements BackupFileBackend {
  const WebBackupFileBackend();

  static const List<XTypeGroup> _types = <XTypeGroup>[
    XTypeGroup(
      label: 'MinuteMeadow backup',
      extensions: <String>['json'],
      mimeTypes: <String>['application/json'],
    ),
  ];

  static const Set<String> _textTypes = <String>{
    'application/json',
    'text/json',
    'text/plain',
    'application/octet-stream',
  };

  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    final file = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: fileName,
    );
    await file.saveTo(fileName);
    return true;
  }

  @override
  Future<Uint8List?> load() async {
    final file = await openFile(acceptedTypeGroups: _types);
    if (file == null) return null;
    final mimeType = file.mimeType?.split(';').first.trim().toLowerCase();
    final extensionIsJson = file.name.toLowerCase().endsWith('.json');
    if (!extensionIsJson &&
        (mimeType == null || !_textTypes.contains(mimeType))) {
      throw const BackupFileException(BackupFileError.unsupportedType);
    }
    final length = await file.length();
    if (length > maxBackupFileBytes) {
      throw BackupFileException(BackupFileError.tooLarge, size: length);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBackupFileBytes) {
      throw BackupFileException(BackupFileError.tooLarge, size: bytes.length);
    }
    return bytes;
  }
}

BackupFileBackend? createWebBackupFileBackend() =>
    const WebBackupFileBackend();
