import 'dart:async';

import 'package:companion_focus/design/companion_theme.dart';
import 'package:companion_focus/features/focus/ambience/ambience.dart';
import 'package:companion_focus/features/settings/focus_ambience_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingEngine implements FocusAmbienceEngine {
  final List<String> calls = <String>[];
  bool failStart = false;

  @override
  Future<void> start(FocusAmbienceTrack track, double volume) async {
    calls.add('start:${track.name}:${_level(volume)}');
    if (failStart) {
      failStart = false;
      throw StateError('No audio route.');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:${_level(volume)}');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  static String _level(double value) => value.toStringAsFixed(2);
}

/// Holds a start open so a test can observe the controller mid-start.
class _PendingEngine extends _RecordingEngine {
  final Completer<void> accepted = Completer<void>();

  @override
  Future<void> start(FocusAmbienceTrack track, double volume) async {
    await super.start(track, volume);
    await accepted.future;
  }
}

const _rain = FocusAmbiencePreferences(track: FocusAmbienceTrack.rain);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preferences', () {
    test('default to explicit Off at a low volume', () {
      const preferences = FocusAmbiencePreferences();

      expect(preferences.track, FocusAmbienceTrack.off);
      expect(preferences.volume, 0.3);
      expect(preferences.isActive, isFalse);
      expect(FocusAmbiencePreferences.fromMap(null), preferences);
    });

    test('round-trip the persistence map', () {
      const preferences = FocusAmbiencePreferences(
        track: FocusAmbienceTrack.wind,
        volume: 0.45,
      );

      expect(
        FocusAmbiencePreferences.fromMap(preferences.toMap()),
        preferences,
      );
      expect(preferences.toMap(), <String, Object>{
        'track': 'wind',
        'volume': 0.45,
      });
    });

    test('treat missing fields as defaults and ignore unknown keys', () {
      expect(
        FocusAmbiencePreferences.fromMap(<String, Object?>{
          'track': 'rain',
          'volume': 0.4,
          'future': true,
        }),
        const FocusAmbiencePreferences(
          track: FocusAmbienceTrack.rain,
          volume: 0.4,
        ),
      );
      expect(
        FocusAmbiencePreferences.fromMap(<String, Object?>{}),
        const FocusAmbiencePreferences(),
      );
    });

    test('reject malformed persistence values', () {
      expect(
        () => FocusAmbiencePreferences.fromMap(<String, Object?>{
          'track': 'storm',
        }),
        throwsFormatException,
      );
      expect(
        () => FocusAmbiencePreferences.fromMap(<String, Object?>{
          'volume': 2.0,
        }),
        throwsFormatException,
      );
      expect(
        () => FocusAmbiencePreferences.fromMap(<String, Object?>{
          'volume': 'loud',
        }),
        throwsFormatException,
      );
      expect(
        () => FocusAmbiencePreferences.fromMap('rain'),
        throwsFormatException,
      );
    });
  });

  group('controller', () {
    test('stays silent for Off and starts once a track is eligible', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(engine: engine);

      await controller.setVisible(true);
      expect(engine.calls, isEmpty);

      await controller.apply(_rain);
      expect(engine.calls, <String>['start:rain:0.30']);
      expect(controller.isPlaying, isTrue);
    });

    test('reports playing only after the platform accepts the start', () async {
      final engine = _PendingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      final pending = controller.setVisible(true);
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, <String>['start:rain:0.30']);
      expect(controller.isPlaying, isFalse);

      engine.accepted.complete();
      await pending;
      expect(controller.isPlaying, isTrue);
    });

    test('seeded background lifecycle stays silent until resumed', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
        initialLifecycle: AppLifecycleState.paused,
      );

      await controller.setVisible(true);
      expect(engine.calls, isEmpty);
      expect(controller.isPlaying, isFalse);

      await controller.setLifecycle(AppLifecycleState.resumed);
      expect(engine.calls, <String>['start:rain:0.30']);
      expect(controller.isPlaying, isTrue);
    });

    test('hidden, background and paused each stop exactly once', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      await controller.setVisible(false);
      await controller.setVisible(false);
      expect(engine.calls, <String>['start:rain:0.30', 'stop']);
      expect(controller.isPlaying, isFalse);

      await controller.setVisible(true);
      await controller.setLifecycle(AppLifecycleState.inactive);
      await controller.setLifecycle(AppLifecycleState.hidden);
      await controller.setLifecycle(AppLifecycleState.paused);
      expect(engine.calls, <String>[
        'start:rain:0.30',
        'stop',
        'start:rain:0.30',
        'stop',
      ]);

      await controller.setLifecycle(AppLifecycleState.resumed);
      expect(engine.calls.last, 'start:rain:0.30');
    });

    test('headphone disconnect stops and reconnect resumes', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      await controller.setHeadphonesConnected(false);
      await controller.setHeadphonesConnected(false);
      expect(engine.calls, <String>['start:rain:0.30', 'stop']);

      await controller.setHeadphonesConnected(true);
      expect(engine.calls.last, 'start:rain:0.30');
    });

    test('re-entering Focus starts a fresh visit', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      await controller.setHeadphonesConnected(false);
      await controller.setVisible(false);
      await controller.setVisible(true);

      expect(engine.calls, <String>[
        'start:rain:0.30',
        'stop',
        'start:rain:0.30',
      ]);
    });

    test('a track change restarts while a volume change stays in place', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      await controller.apply(
        const FocusAmbiencePreferences(
          track: FocusAmbienceTrack.wind,
          volume: 0.3,
        ),
      );
      expect(engine.calls, <String>[
        'start:rain:0.30',
        'stop',
        'start:wind:0.30',
      ]);

      await controller.apply(
        const FocusAmbiencePreferences(
          track: FocusAmbienceTrack.wind,
          volume: 0.5,
        ),
      );
      expect(engine.calls.last, 'volume:0.50');

      await controller.apply(
        const FocusAmbiencePreferences(
          track: FocusAmbienceTrack.wind,
          volume: 0.5,
        ),
      );
      expect(engine.calls.last, 'volume:0.50');
    });

    test('zero volume silences the selected track without clearing it', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      await controller.apply(
        const FocusAmbiencePreferences(
          track: FocusAmbienceTrack.rain,
          volume: 0,
        ),
      );
      expect(engine.calls, <String>['start:rain:0.30', 'stop']);
      expect(controller.preferences.track, FocusAmbienceTrack.rain);

      await controller.apply(_rain);
      expect(engine.calls.last, 'start:rain:0.30');
    });

    test('dispose is idempotent and late calls are ignored', () async {
      final engine = _RecordingEngine();
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      await controller.dispose();
      await controller.dispose();
      await controller.setVisible(true);
      await controller.apply(_rain);
      await controller.setHeadphonesConnected(false);

      expect(engine.calls, <String>['start:rain:0.30', 'stop']);
      expect(controller.isPlaying, isFalse);
    });

    test('a failed start never leaves playback marked active', () async {
      final engine = _RecordingEngine()..failStart = true;
      final controller = FocusAmbienceController(
        engine: engine,
        preferences: _rain,
      );

      await controller.setVisible(true);
      expect(controller.isPlaying, isFalse);

      await controller.setVisible(false);
      expect(engine.calls, <String>['start:rain:0.30']);
    });
  });

  group('platform channel', () {
    const channel = MethodChannel(FocusAmbiencePlayer.channelName);
    late List<MethodCall> calls;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('uses its own channel and the documented methods', () async {
      final player = FocusAmbiencePlayer();
      addTearDown(player.detach);

      await player.start(FocusAmbienceTrack.rain, 0.3);
      await player.setVolume(0.45);
      await player.stop();

      expect(calls.map((call) => call.method), <String>[
        'start',
        'setVolume',
        'stop',
      ]);
      final start = calls.first.arguments as Map<Object?, Object?>;
      expect(start['track'], 'rain');
      expect(start['volume'], 0.3);
      final volume = calls[1].arguments as Map<Object?, Object?>;
      expect(volume['volume'], 0.45);

      expect(
        FocusAmbiencePlayer.channelName,
        isNot('app.companionfocus/pack_sound'),
      );
      expect(
        FocusAmbiencePlayer.channelName,
        isNot('app.companionfocus/timer_feedback'),
      );
    });

    test('does nothing off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final player = FocusAmbiencePlayer();
      addTearDown(player.detach);

      await player.start(FocusAmbienceTrack.wind, 0.4);
      await player.setVolume(0.5);
      await player.stop();

      expect(calls, isEmpty);
    });

    test('a missing host is not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final player = FocusAmbiencePlayer();
      addTearDown(player.detach);

      await player.start(FocusAmbienceTrack.rain, 0.3);
      await player.stop();
    });
  });

  group('page', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('lists Off, Rain and Volume and saves each choice', (
      tester,
    ) async {
      final saves = <FocusAmbiencePreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: CompanionTheme.light,
          home: FocusAmbiencePage(
            preferences: const FocusAmbiencePreferences(),
            onSave: (next) async => saves.add(next),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Off'), findsWidgets);
      expect(find.text('Rain'), findsWidgets);
      expect(find.text('Volume'), findsWidgets);
      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.text('Rain').first);
      await tester.pumpAndSettle();
      expect(saves.last.track, FocusAmbienceTrack.rain);

      await tester.tap(find.text('Off').first);
      await tester.pumpAndSettle();
      expect(saves.last.track, FocusAmbienceTrack.off);

      await tester.drag(find.byType(Slider), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(saves.last.volume, greaterThan(0.3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('returns to the saved value when a save fails', (
      tester,
    ) async {
      var fail = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: CompanionTheme.light,
          home: FocusAmbiencePage(
            preferences: const FocusAmbiencePreferences(),
            onSave: (next) async {
              if (fail) throw StateError('No storage.');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      fail = true;
      await tester.tap(find.text('Rain').first);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save Focus ambience. Try again.'),
        findsOneWidget,
      );
      final rain = tester.widget<ChoiceChip>(
        find.byKey(FocusAmbiencePage.trackKey(FocusAmbienceTrack.rain)),
      );
      expect(rain.selected, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
