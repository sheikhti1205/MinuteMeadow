import 'package:flutter/widgets.dart';

import 'focus_ambience_engine.dart';
import 'focus_ambience_preferences.dart';

/// Owns the one decision about whether quiet Focus ambience may play.
///
/// Playback requires all of these at once: the Focus surface is visible, the
/// app is resumed, headphones have not been disconnected, and the saved choice
/// is an audible track at a positive volume. Leaving any condition stops the
/// loop once; returning restarts it, and re-entering Focus adopts the current
/// audio route again. Every public method is serialized, so a fast track change
/// cannot interleave a stale start with a new stop.
class FocusAmbienceController {
  FocusAmbienceController({
    required FocusAmbienceEngine engine,
    FocusAmbiencePreferences preferences = const FocusAmbiencePreferences(),
    AppLifecycleState initialLifecycle = AppLifecycleState.resumed,
  }) : _engine = engine,
       _preferences = preferences,
       _lifecycle = initialLifecycle;

  final FocusAmbienceEngine _engine;
  FocusAmbiencePreferences _preferences;

  /// Seeded from the real app lifecycle so a controller created while the app
  /// is already backgrounded stays silent until the next resume.
  AppLifecycleState _lifecycle;
  bool _visible = false;
  bool _headphones = true;
  bool _playing = false;
  bool _disposed = false;
  bool _disposeRequested = false;
  Future<void> _queue = Future<void>.value();
  Future<void> _disposeFuture = Future<void>.value();

  FocusAmbiencePreferences get preferences => _preferences;

  /// True only after the platform accepted a start, until the loop stops.
  bool get isPlaying => _playing;

  bool get _eligible =>
      !_disposed &&
      _visible &&
      _lifecycle == AppLifecycleState.resumed &&
      _headphones &&
      _preferences.isActive;

  /// Adopts a saved preference. A track change restarts the loop; a volume
  /// change updates the running track in place.
  Future<void> apply(FocusAmbiencePreferences next) {
    if (_disposeRequested) return _queue;
    return _enqueue(() async {
      if (_disposed) return;
      final previous = _preferences;
      _preferences = next;
      if (next.track != previous.track && _playing) {
        _playing = false;
        await _stop();
      }
      if (next.volume != previous.volume && _playing && next.isActive) {
        await _setVolume(next.volume);
      }
      await _sync();
    });
  }

  /// True only while the Focus surface is on screen.
  ///
  /// Returning to the surface starts a fresh visit, so an earlier headphone
  /// disconnect only silences the visit in which it happened.
  Future<void> setVisible(bool visible) {
    if (_disposeRequested) return _queue;
    return _enqueue(() async {
      if (_disposed) return;
      if (visible && !_visible) _headphones = true;
      _visible = visible;
      await _sync();
    });
  }

  /// Only [AppLifecycleState.resumed] allows playback.
  Future<void> setLifecycle(AppLifecycleState state) {
    if (_disposeRequested) return _queue;
    return _enqueue(() async {
      if (_disposed) return;
      _lifecycle = state;
      await _sync();
    });
  }

  /// A disconnect stops at once and silences the rest of the current visit.
  Future<void> setHeadphonesConnected(bool connected) {
    if (_disposeRequested) return _queue;
    return _enqueue(() async {
      if (_disposed) return;
      _headphones = connected;
      await _sync();
    });
  }

  Future<void> _sync() async {
    if (_disposed) {
      if (_playing) {
        _playing = false;
        await _stop();
      }
      return;
    }
    if (_eligible) {
      if (_playing) return;
      try {
        // The flag flips only when the platform accepted the start, so
        // [isPlaying] never claims audio that has not begun.
        await _engine.start(_preferences.track, _preferences.volume);
        _playing = true;
      } catch (_) {
        // A route that cannot start stays idle and can be retried.
      }
      return;
    }
    if (!_playing) return;
    _playing = false;
    await _stop();
  }

  Future<void> _setVolume(double volume) async {
    try {
      await _engine.setVolume(volume);
    } catch (_) {
      // The saved preference is unchanged, so the next start uses it.
    }
  }

  Future<void> _stop() async {
    try {
      await _engine.stop();
    } catch (_) {
      // A missing audio route must not break lifecycle handling.
    }
  }

  /// Stops playback and ignores every later request. Safe to call twice.
  Future<void> dispose() {
    if (_disposeRequested) return _disposeFuture;
    _disposeRequested = true;
    _disposeFuture = _enqueue(() async {
      _disposed = true;
      if (_playing) {
        _playing = false;
        await _stop();
      }
    });
    return _disposeFuture;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
