# 0001: Flutter for the Android app

Status: Accepted

The app needs a shared layout and drawing API for Android and browser previews. Use Flutter and Dart for the app, with Kotlin reserved for Android APIs that Flutter packages cannot cover reliably.

A native Android app would remove the Flutter dependency but require a separate browser preview. Flutter gives both targets the same UI and compositor code. Android lifecycle behavior and permission handling still need verification on Android.
