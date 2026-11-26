import 'package:companion_focus/companion_engine/animation/state_controller.dart';
import 'package:companion_focus/companion_engine/rig/rig_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RigStateController', () {
    test('starts on the default clip with no requested animation', () {
      final controller = RigStateController(_buildRig());

      expect(controller.defaultClip, 'idle');
      expect(controller.activeRequest, isNull);
      expect(controller.activeName, isNull);
      expect(controller.queuedRequests, isEmpty);
      expect(controller.isAnimating, isFalse);
      expect(controller.isPaused, isFalse);
      expect(controller.activeTimeMs, isNull);
      expect(controller.sample()['body']?.offsetX, 0);
    });

    test('a named request becomes the active request', () {
      final controller = RigStateController(_buildRig());

      final request = controller.request(
        'a',
        priority: 3,
        interruptible: false,
      );

      expect(controller.activeRequest, same(request));
      expect(controller.activeName, 'a');
      expect(controller.isAnimating, isTrue);
      expect(controller.queuedCount, 0);
    });

    test('higher priority interrupts and lower priority queues', () {
      final controller = RigStateController(_buildRig());

      controller.request('a', priority: 5, interruptible: false);
      final queued = controller.request('b', priority: 3);
      expect(controller.activeName, 'a');
      expect(controller.queuedRequests.single, same(queued));

      final urgent = controller.request('quick', priority: 9);
      expect(controller.activeRequest, same(urgent));
      expect(controller.activeName, 'quick');
      expect(controller.queuedRequests.single, same(queued));

      final events = controller.advance(500);
      expect(
        events.whereType<RigStateCompletionEvent>().map(
          (event) => event.requestName,
        ),
        <String>['quick'],
      );
      expect(controller.activeName, 'b');
    });

    test('equal priority interrupts only an interruptible request', () {
      final controller = RigStateController(_buildRig());

      controller.request('a', priority: 1, interruptible: false);
      controller.request('b', priority: 1);
      expect(controller.activeName, 'a');
      expect(controller.queuedCount, 1);

      controller.clear();
      controller.request('a', priority: 1);
      controller.request('b', priority: 1);
      expect(controller.activeName, 'b');
      expect(controller.queuedCount, 0);
    });

    test('blends transforms and opacity across a request transition', () {
      final controller = RigStateController(_buildRig());

      controller.request('a', transition: const Duration(milliseconds: 100));
      var sample = controller.sample();
      expect(sample['body']?.offsetX, closeTo(0, 0.0001));
      expect(sample['body']?.opacity, closeTo(1, 0.0001));
      expect(sample['body']?.scaleX, closeTo(1, 0.0001));

      controller.advance(50);
      sample = controller.sample();
      expect(sample['body']?.offsetX, closeTo(50, 0.0001));
      expect(sample['body']?.opacity, closeTo(0.6, 0.0001));
      expect(sample['body']?.scaleX, closeTo(1.5, 0.0001));
      expect(controller.isTransitioning, isTrue);
      expect(controller.transitionProgress, closeTo(0.5, 0.0001));

      controller.advance(50);
      sample = controller.sample();
      expect(sample['body']?.offsetX, closeTo(100, 0.0001));
      expect(sample['body']?.opacity, closeTo(0.2, 0.0001));
      expect(sample['body']?.scaleX, closeTo(2, 0.0001));
      expect(controller.isTransitioning, isFalse);
      expect(controller.transitionProgress, 1);
    });

    test('interrupting mid-transition blends from the visible pose', () {
      final controller = RigStateController(_buildRig());

      controller.request('a', transition: const Duration(milliseconds: 100));
      controller.advance(50);
      expect(controller.sample()['body']?.offsetX, closeTo(50, 0.0001));

      controller.request(
        'b',
        priority: 10,
        transition: const Duration(milliseconds: 100),
      );
      expect(controller.sample()['body']?.offsetX, closeTo(50, 0.0001));

      controller.advance(50);
      expect(controller.sample()['body']?.offsetX, closeTo(125, 0.0001));
    });

    test('one-shot completion returns to the default and fires once', () {
      final controller = RigStateController(_buildRig());

      controller.request('quick', transition: Duration.zero);
      expect(controller.sample()['body']?.offsetX, closeTo(0, 0.0001));

      final events = controller.advance(500);
      expect(events.whereType<RigStateCompletionEvent>(), hasLength(1));
      expect(controller.activeName, isNull);
      expect(controller.isAnimating, isFalse);
      expect(controller.sample()['body']?.offsetX, 0);

      final repeated = controller.advance(100);
      expect(repeated.whereType<RigStateCompletionEvent>(), isEmpty);
    });

    test('markers fire in order once per activation', () {
      final controller = RigStateController(_buildRig());
      const markers = <RigStateMarker>[
        RigStateMarker(name: 'start', timeMs: 0),
        RigStateMarker(name: 'middle', timeMs: 200),
        RigStateMarker(name: 'end', timeMs: 500),
      ];
      controller.request(
        'quick',
        transition: Duration.zero,
        markers: markers,
      );

      expect(_markerNames(controller.advance(100)), <String>['start']);
      expect(_markerNames(controller.advance(100)), <String>['middle']);
      expect(_markerNames(controller.advance(299)), isEmpty);

      final finalEvents = controller.advance(1);
      expect(_markerNames(finalEvents), <String>['end']);
      expect(finalEvents.last, isA<RigStateCompletionEvent>());

      controller.request(
        'quick',
        transition: Duration.zero,
        markers: markers,
      );
      expect(_markerNames(controller.advance(1)), <String>['start']);
    });

    test('markers keep insertion order when times are equal', () {
      final controller = RigStateController(_buildRig());

      controller.request(
        'quick',
        transition: Duration.zero,
        markers: const <RigStateMarker>[
          RigStateMarker(name: 'markerB', timeMs: 100),
          RigStateMarker(name: 'markerA', timeMs: 100),
        ],
      );

      expect(
        _markerNames(controller.advance(100)),
        <String>['markerB', 'markerA'],
      );
    });

    test('pause freezes playback, markers and blending until resumed', () {
      final controller = RigStateController(_buildRig());
      controller.request(
        'quick',
        transition: Duration.zero,
        markers: const <RigStateMarker>[
          RigStateMarker(name: 'late', timeMs: 450),
        ],
      );

      controller.advance(100);
      controller.pause();
      expect(controller.isPaused, isTrue);
      expect(controller.advance(1000), isEmpty);
      expect(controller.activeTimeMs, closeTo(100, 0.0001));

      controller.resume();
      expect(_markerNames(controller.advance(350)), <String>['late']);
      expect(controller.activeName, 'quick');

      final events = controller.advance(50);
      expect(events.whereType<RigStateCompletionEvent>(), hasLength(1));
      expect(controller.activeName, isNull);
    });

    test('pause freezes an in-flight transition', () {
      final controller = RigStateController(_buildRig());
      controller.request('a', transition: const Duration(milliseconds: 100));
      controller.advance(50);

      controller.pause();
      expect(controller.advance(100), isEmpty);
      expect(controller.sample()['body']?.offsetX, closeTo(50, 0.0001));
      expect(controller.transitionProgress, closeTo(0.5, 0.0001));

      controller.resume();
      controller.advance(50);
      expect(controller.isTransitioning, isFalse);
      expect(controller.sample()['body']?.offsetX, closeTo(100, 0.0001));
    });

    test('queued requests run by priority after completion', () {
      final controller = RigStateController(_buildRig());

      controller.request('hold', priority: 10, interruptible: false);
      final low = controller.request('b', priority: 1);
      final high = controller.request('quick', priority: 5);

      expect(
        controller.queuedRequests.map((request) => request.name),
        <String>['quick', 'b'],
      );
      expect(controller.queuedRequests.first, same(high));
      expect(controller.queuedRequests.last, same(low));

      controller.advance(300);
      expect(controller.activeName, 'quick');
      expect(controller.queuedRequests.single, same(low));

      controller.advance(500);
      expect(controller.activeName, 'b');
      expect(controller.queuedCount, 0);
    });

    test('rejects unknown clips and out-of-range markers', () {
      final controller = RigStateController(_buildRig());

      expect(() => controller.request('missing'), throwsArgumentError);
      expect(
        () => controller.request(
          'quick',
          markers: const <RigStateMarker>[
            RigStateMarker(name: 'tooLate', timeMs: 600),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('cancel and clear return to the default state', () {
      final controller = RigStateController(_buildRig());

      controller.request('a');
      controller.request('b', priority: -1);
      expect(controller.queuedCount, 1);

      controller.cancelActive();
      expect(controller.activeName, 'b');
      expect(controller.queuedCount, 0);

      controller.request('a');
      controller.request('b', priority: -1);
      controller.clear();
      expect(controller.activeName, isNull);
      expect(controller.queuedCount, 0);
      expect(controller.sample()['body']?.offsetX, 0);
    });
  });
}

List<String> _markerNames(List<RigStateEvent> events) => <String>[
  for (final event in events.whereType<RigStateMarkerEvent>())
    event.marker.name,
];

CompanionRig _buildRig() {
  const region = SpriteRegion(
    atlas: 'test',
    x: 0,
    y: 0,
    width: 8,
    height: 8,
  );
  return CompanionRig(
    canvasWidth: 16,
    canvasHeight: 16,
    atlases: const <String, AtlasDefinition>{
      'test': AtlasDefinition(id: 'test', width: 8, height: 8),
    },
    layers: const <LayerDefinition>[
      LayerDefinition(id: 'body', defaultFrame: region),
    ],
    clips: <String, ClipDefinition>{
      'idle': ClipDefinition(
        id: 'idle',
        durationMs: 1000,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetX,
                keyframes: const <Keyframe>[Keyframe(timeMs: 0, value: 0)],
              ),
            ],
          ),
        ],
      ),
      'a': ClipDefinition(
        id: 'a',
        durationMs: 1000,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetX,
                keyframes: const <Keyframe>[Keyframe(timeMs: 0, value: 100)],
              ),
              PropertyTrack(
                property: LayerProperty.opacity,
                keyframes: const <Keyframe>[Keyframe(timeMs: 0, value: 0.2)],
              ),
              PropertyTrack(
                property: LayerProperty.scaleX,
                keyframes: const <Keyframe>[Keyframe(timeMs: 0, value: 2)],
              ),
            ],
          ),
        ],
      ),
      'b': ClipDefinition(
        id: 'b',
        durationMs: 1000,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetX,
                keyframes: const <Keyframe>[Keyframe(timeMs: 0, value: 200)],
              ),
            ],
          ),
        ],
      ),
      'quick': ClipDefinition(
        id: 'quick',
        durationMs: 500,
        loop: false,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetX,
                keyframes: const <Keyframe>[
                  Keyframe(timeMs: 0, value: 0),
                  Keyframe(timeMs: 500, value: 50),
                ],
              ),
            ],
          ),
        ],
      ),
      'hold': ClipDefinition(
        id: 'hold',
        durationMs: 300,
        loop: false,
        layers: <LayerClip>[
          LayerClip(
            layerId: 'body',
            tracks: <PropertyTrack>[
              PropertyTrack(
                property: LayerProperty.offsetX,
                keyframes: const <Keyframe>[Keyframe(timeMs: 0, value: 25)],
              ),
            ],
          ),
        ],
      ),
    },
    defaultClip: 'idle',
  );
}
