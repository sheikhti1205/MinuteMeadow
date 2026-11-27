import 'focus_ambience_preferences.dart';

/// The playback boundary used by [FocusAmbienceController].
///
/// A platform player and a unit-test double both implement this. Methods are
/// asynchronous so the controller can serialize a start, a volume change and a
/// stop without blocking the widget tree.
abstract interface class FocusAmbienceEngine {
  /// Starts or replaces the loop for [track] at [volume].
  Future<void> start(FocusAmbienceTrack track, double volume);

  /// Adjusts a running loop without restarting it.
  Future<void> setVolume(double volume);

  /// Stops and releases the loop. Calling it while stopped is a no-op.
  Future<void> stop();
}
