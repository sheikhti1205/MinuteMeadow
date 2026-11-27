/// The quiet tracks a Focus session can play.
///
/// [FocusAmbienceTrack.off] is the explicit default, so a fresh install stays
/// silent until the user chooses a sound. The tracks are original procedural
/// loops, never bundled audio files or pack assets.
enum FocusAmbienceTrack { off, rain, wind }

extension FocusAmbienceTrackInfo on FocusAmbienceTrack {
  String get label => switch (this) {
    FocusAmbienceTrack.off => 'Off',
    FocusAmbienceTrack.rain => 'Rain',
    FocusAmbienceTrack.wind => 'Wind',
  };

  /// The stable identifier understood by the Android player.
  String get id => switch (this) {
    FocusAmbienceTrack.off => 'off',
    FocusAmbienceTrack.rain => 'rain',
    FocusAmbienceTrack.wind => 'wind',
  };
}

/// The saved ambience choice, independent of completion sound and haptics.
///
/// The object is a plain value. [toMap] is the additive `focusAmbience`
/// document that `AppSettings` stores and backs up, so older settings files
/// without the key keep decoding to the silent default.
class FocusAmbiencePreferences {
  const FocusAmbiencePreferences({
    this.track = FocusAmbienceTrack.off,
    this.volume = defaultVolume,
  });

  /// The key this document is stored under in settings and backups.
  static const settingsKey = 'focusAmbience';

  /// Ambience starts quiet rather than at a music-player level.
  static const defaultVolume = 0.3;
  static const minVolume = 0.0;
  static const maxVolume = 1.0;

  final FocusAmbienceTrack track;
  final double volume;

  bool get isActive => track != FocusAmbienceTrack.off && volume > 0;

  FocusAmbiencePreferences copyWith({
    FocusAmbienceTrack? track,
    double? volume,
  }) => FocusAmbiencePreferences(
    track: track ?? this.track,
    volume: volume ?? this.volume,
  );

  Map<String, Object> toMap() => <String, Object>{
    'track': track.id,
    'volume': volume,
  };

  /// Decodes the additive settings document.
  ///
  /// A missing document returns the silent default. Unknown keys are ignored so
  /// a newer backup still restores on this build, while malformed values are
  /// rejected instead of silently changing the user's choice.
  static FocusAmbiencePreferences fromMap(Object? map) {
    if (map == null) return const FocusAmbiencePreferences();
    if (map is! Map<String, Object?>) {
      throw const FormatException('Invalid Focus ambience preferences.');
    }
    final track = switch (map['track']) {
      null => FocusAmbienceTrack.off,
      'off' => FocusAmbienceTrack.off,
      'rain' => FocusAmbienceTrack.rain,
      'wind' => FocusAmbienceTrack.wind,
      _ => throw const FormatException('Invalid Focus ambience track.'),
    };
    final volume = switch (map['volume']) {
      null => defaultVolume,
      double value when value >= minVolume && value <= maxVolume => value,
      int value when value >= minVolume && value <= maxVolume =>
        value.toDouble(),
      _ => throw const FormatException('Invalid Focus ambience volume.'),
    };
    return FocusAmbiencePreferences(track: track, volume: volume);
  }

  @override
  bool operator ==(Object other) =>
      other is FocusAmbiencePreferences &&
      other.track == track &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(track, volume);
}
