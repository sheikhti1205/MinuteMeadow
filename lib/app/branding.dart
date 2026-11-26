abstract final class Branding {
  static const name = 'MinuteMeadow';

  /// The public semantic version. Keep this MAJOR.MINOR.PATCH, because pack
  /// manifests compare their minimum application version against it.
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  /// The Android version code supplied by CI, or zero for a local build.
  static const buildNumber = int.fromEnvironment('APP_BUILD_NUMBER');

  /// The complete CI build identifier, empty for a local build.
  static const buildId = String.fromEnvironment('APP_BUILD_ID');

  /// The identifier to show to people: the CI build when present, otherwise
  /// the plain semantic version.
  static String get displayVersion => buildId.isEmpty ? version : buildId;
}
