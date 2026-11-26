import 'package:flutter/foundation.dart';

import '../../app/branding.dart';
import 'companion_library.dart';
import 'pack_bundle.dart';

/// Owns the installed companion library and its persisted snapshot.
///
/// A change is validated, encoded and handed to [onSnapshot] before the new
/// library is adopted. If the write fails, the previously installed packs stay
/// in use, so a rejected install or update never removes working content.
class CompanionSession extends ChangeNotifier {
  CompanionSession({
    required String? initialSnapshot,
    required Future<void> Function(String) onSnapshot,
    DateTime Function()? now,
  }) : _onSnapshot = onSnapshot,
       _now = now ?? DateTime.now {
    final result = CompanionLibrary.decode(initialSnapshot);
    _library = result.library;
    _rejected = result.rejected;
    _loadError = result.error;
  }

  final Future<void> Function(String) _onSnapshot;
  final DateTime Function() _now;

  CompanionLibrary _library = CompanionLibrary.empty;
  int _rejected = 0;
  String? _loadError;
  String? _error;
  String? _success;
  bool _busy = false;
  String? _busyPack;
  bool _disposed = false;

  CompanionLibrary get library => _library;

  /// Installed packs skipped because their stored record no longer validates.
  int get rejected => _rejected;

  /// A snapshot that could not be read at all, shown once with the empty shelf.
  String? get loadError => _loadError;

  /// The last failed operation, or null.
  String? get error => _error;

  /// The last completed operation, or null.
  String? get success => _success;

  bool get busy => _busy;
  String? get busyPack => _busyPack;

  void dismissLoadNotice() {
    if (_loadError == null && _rejected == 0) return;
    _loadError = null;
    _rejected = 0;
    _announce();
  }

  Future<bool> importText(String text) => installPack(() => PackBundle.decode(text));

  Future<bool> importBytes(Uint8List bytes) => installPack(() => PackBundle.fromUpload(bytes));

  /// Installs the bundle built by [source] through the shared install path.
  ///
  /// The bundle is constructed and fully validated inside the busy state so a
  /// damaged file surfaces as an inline error instead of an exception.
  Future<bool> installPack(PackBundle Function() source) => _apply(() {
    final bundle = source();
    final manifest = bundle.manifest;
    if (!manifest.isCompatibleWith(Branding.version)) {
      throw FormatException(
        '${manifest.name} needs ${Branding.name} ${manifest.minimumAppVersion} or newer.',
      );
    }
    return (
      library: _library.install(
        InstalledPack(
          manifest: manifest,
          assets: bundle.assets,
          installedAt: _now(),
        ),
      ),
      message: '${manifest.name} ${manifest.version} installed.',
    );
  });

  Future<bool> remove(String id) {
    final pack = _library.pack(id);
    if (pack == null) return Future<bool>.value(false);
    return _apply(
      () => (
        library: _library.remove(id),
        message: '${pack.manifest.name} removed.',
      ),
      packId: id,
    );
  }

  Future<bool> _apply(
    ({CompanionLibrary library, String message}) Function() build, {
    String? packId,
  }) async {
    if (_busy) return false;
    _busy = true;
    _busyPack = packId;
    _error = null;
    _success = null;
    _announce();
    try {
      final candidate = build();
      final encoded = candidate.library.encode();
      await _onSnapshot(encoded);
      _library = candidate.library;
      _success = candidate.message;
      _loadError = null;
      return true;
    } on FormatException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Could not save the companion library.';
      return false;
    } finally {
      _busy = false;
      _busyPack = null;
      _announce();
    }
  }

  void _announce() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
