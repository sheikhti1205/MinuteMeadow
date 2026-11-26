# Testing

GitHub Actions analyzes Dart source, runs Flutter tests, and builds the Android debug APK and web app. Those checks do not run the app on an Android device.

The Android integration workflow runs the application on an emulator. It checks the native elapsed clock bridge, saves a focus preference through Settings, and reopens the app against a saved SQLite checkpoint.

Timer tests should advance a controlled clock, rather than wait in real time. Cover valid and rejected transitions, remaining time after pause and restore, wall-clock changes, and duplicate completion. Verify that completed history and active timer state survive interruption without recording the same session twice.

Use widget tests for tab navigation, empty states and important controls. Run Android checks for backgrounding, process death, reboot, notification denial and battery saver. Check both themes, narrow portrait layouts, text scaling and screen-reader labels.

Use geometric fixtures to test drawing, hitboxes and interaction events. Pack tests should cover invalid manifests, unsafe paths, oversized assets and failed upgrades that leave the installed version usable.

To include the Animation laboratory and geometric catalogue in a web test build, dispatch **Flutter CI** with **Include the Animation laboratory and geometric catalogue in the web artifact** enabled. Serve the resulting `companion-focus-web` artifact as static files. The normal web build omits those tools.
