# Companion Focus

Companion Focus is an Android app in early development. Its first release will combine a focus timer, stopwatch, session history, and installable pixel-art companion packs.

## Build

Use Flutter 3.44.0 and the [Android development setup](https://docs.flutter.dev/platform-integration/android/setup).

```sh
flutter create --empty --no-pub --platforms=android,web --org=app.companionfocus --project-name=companion_focus .
flutter pub get
flutter run
```

GitHub Actions runs static analysis, tests, and Android and web builds. No app binaries have been released.

See the [roadmap](ROADMAP.md) for planned features. A distribution license has not been selected.
