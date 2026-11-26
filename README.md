# Companion Focus

Companion Focus is an Android app in development for focus sessions, breaks, stopwatch laps and countdowns. It stores settings and session history on the device. You can import and manage companion packs without an account. The bundled catalogue starts empty.

## Build

Use Flutter 3.44.0 and the [Android development setup](https://docs.flutter.dev/platform-integration/android/setup).

```sh
flutter create --empty --no-pub --platforms=android,web --org=app.companionfocus --project-name=companion_focus .
git show HEAD:pubspec.lock > pubspec.lock
flutter pub get --enforce-lockfile
flutter run
```

GitHub Actions runs static analysis, tests, and Android and web builds. The separate Android integration workflow runs on an emulator. No app binaries have been released.

See the [roadmap](ROADMAP.md) for planned features. A distribution license has not been selected.
