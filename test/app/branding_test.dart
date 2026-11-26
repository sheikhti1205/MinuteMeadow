import 'dart:io';

import 'package:companion_focus/app/branding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the local version matches the pubspec semantic base', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d{1,3}\.\d{1,3}\.\d{1,3})(?:\+\d+)?\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(Branding.version, match!.group(1));
  });

  test('a local build has no CI build metadata', () {
    expect(Branding.buildNumber, 0);
    expect(Branding.buildId, isEmpty);
    expect(Branding.displayVersion, Branding.version);
  });
}
