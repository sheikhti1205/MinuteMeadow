import 'backup_file_transport_api.dart';

/// Non-web fallback for the browser backend.
///
/// The real implementation is only imported for the web target, so no other
/// platform compiles browser APIs.
BackupFileBackend? createWebBackupFileBackend() => null;
