import 'dart:math' as math;

import '../rig/rig_model.dart';
import 'rig_playback.dart';

/// Default transform and opacity blend used when a request replaces the
/// visible state.
const Duration rigStateDefaultTransition = Duration(milliseconds: 120);

/// A named milestone inside one animation request. Times are measured from the
/// start of the request activation and fire once per activation.
final class RigStateMarker {
  const RigStateMarker({required this.name, required this.timeMs})
    : assert(timeMs >= 0);

  final String name;
  final int timeMs;
}

/// Immutable metadata for one animation request.
///
/// [name] is the clip id. [priority] orders requests: a higher priority always
/// wins, while an equal or lower priority wins only from an interruptible
/// active request. [markers] are sorted by time, keeping insertion order for
/// equal times.
final class RigStateRequest {
  RigStateRequest({
    required this.name,
    this.priority = 0,
    this.interruptible = true,
    this.transition = rigStateDefaultTransition,
    List<RigStateMarker> markers = const <RigStateMarker>[],
  }) : markers = List<RigStateMarker>.unmodifiable(_orderedMarkers(markers));

  final String name;
  final int priority;
  final bool interruptible;
  final Duration transition;
  final List<RigStateMarker> markers;
}

/// Base type for controller output. [advance] returns marker and completion
/// events in that order for the same step.
sealed class RigStateEvent {
  const RigStateEvent({required this.requestName});

  final String requestName;
}

/// A request marker was crossed during an [RigStateController.advance] step.
final class RigStateMarkerEvent extends RigStateEvent {
  const RigStateMarkerEvent({
    required super.requestName,
    required this.marker,
  });

  final RigStateMarker marker;
}

/// A one-shot request reached its clip duration and was cleared.
final class RigStateCompletionEvent extends RigStateEvent {
  const RigStateCompletionEvent({required super.requestName});
}

/// Owns the interaction state above [RigPlayback]. It selects one named active
/// request, queues requests that cannot interrupt it, cross-fades transform and
/// opacity over a short transition, and returns to the default clip when a
/// one-shot completes. Playback time only moves through [advance], so callers
/// can drive it from a deterministic ticker.
final class RigStateController {
  RigStateController(
    this.rig, {
    String? defaultClip,
    Duration defaultTransition = rigStateDefaultTransition,
  }) : _defaultClip = defaultClip ?? rig.defaultClip,
       _defaultTransition = defaultTransition {
    _playback = RigPlayback(rig: rig, defaultClip: _defaultClip);
  }

  final CompanionRig rig;
  final String? _defaultClip;
  final Duration _defaultTransition;

  late final RigPlayback _playback;

  RigStateRequest? _active;
  final List<RigStateRequest> _queued = <RigStateRequest>[];
  final Set<int> _firedMarkers = <int>{};
  double _activeElapsedMs = 0;

  Map<String, LayerAnimation>? _blendFrom;
  double _blendElapsedMs = 0;
  double _blendDurationMs = 0;

  bool _paused = false;

  String? get defaultClip => _defaultClip;

  String? get activeName => _active?.name;

  RigStateRequest? get activeRequest => _active;

  /// Requests waiting for the active request to finish, highest priority first
  /// and oldest first among equal priorities.
  List<RigStateRequest> get queuedRequests =>
      List<RigStateRequest>.unmodifiable(_queued);

  int get queuedCount => _queued.length;

  bool get hasActiveRequest => _active != null;

  /// True while a request or its entry transition is running. The default clip
  /// alone is not considered animation activity.
  bool get isAnimating => _active != null || _blendFrom != null;

  bool get isTransitioning => _blendFrom != null;

  bool get hasBaseMotion {
    final base = _playback.base;
    return base != null && !base.isComplete && base.clip.layers.any(
      (layer) => (layer.frames?.frames.length ?? 0) > 1 || layer.tracks.isNotEmpty,
    );
  }

  bool get isPaused => _paused;

  /// Elapsed time of the active request, or null when nothing is requested.
  double? get activeTimeMs => _active == null ? null : _activeElapsedMs;

  /// Progress of the current blend, from 0 to 1. Returns 1 when idle.
  double get transitionProgress => _blendProgress;

  /// Starts [name] now when possible, otherwise queues it. Unknown clip ids and
  /// markers outside the clip duration are rejected.
  RigStateRequest request(
    String name, {
    int priority = 0,
    bool interruptible = true,
    Duration? transition,
    List<RigStateMarker> markers = const <RigStateMarker>[],
  }) {
    final clip = rig.clipById(name);
    if (clip == null) {
      throw ArgumentError.value(name, 'name', 'Unknown clip id.');
    }
    final request = RigStateRequest(
      name: name,
      priority: priority,
      interruptible: interruptible,
      transition: transition ?? _defaultTransition,
      markers: markers,
    );
    for (final marker in request.markers) {
      if (marker.timeMs < 0 || marker.timeMs > clip.durationMs) {
        throw ArgumentError.value(
          marker.timeMs,
          'markers',
          'Marker "${marker.name}" is outside the clip duration.',
        );
      }
    }

    final active = _active;
    if (active == null || _canInterrupt(active, request)) {
      _activate(request);
    } else {
      _enqueue(request);
    }
    return request;
  }

  /// Advances playback, markers and the active transition by [deltaMs].
  /// Returns an empty list while paused or when the step is not positive.
  List<RigStateEvent> advance(double deltaMs) {
    if (_paused || !deltaMs.isFinite || deltaMs <= 0) {
      return const <RigStateEvent>[];
    }

    final events = <RigStateEvent>[];
    final playbackEvents = _playback.advance(deltaMs);

    if (_blendFrom != null) {
      _blendElapsedMs += deltaMs;
      if (_blendElapsedMs >= _blendDurationMs) {
        _clearBlend();
      }
    }

    final active = _active;
    if (active == null) return events;

    _activeElapsedMs += deltaMs;
    final clip = rig.clipById(active.name);
    final duration = clip?.durationMs.toDouble() ?? _activeElapsedMs;
    final markerLimit = clip != null && !clip.loop
        ? math.min(_activeElapsedMs, duration)
        : _activeElapsedMs;
    for (var index = 0; index < active.markers.length; index++) {
      final marker = active.markers[index];
      if (_firedMarkers.contains(index)) continue;
      if (marker.timeMs <= markerLimit) {
        _firedMarkers.add(index);
        events.add(
          RigStateMarkerEvent(requestName: active.name, marker: marker),
        );
      }
    }

    final completed = playbackEvents.any(
      (event) => event.completed && event.clipId == active.name,
    );
    if (completed) {
      events.add(RigStateCompletionEvent(requestName: active.name));
      _completeActive();
    }
    return events;
  }

  /// Samples the active request blended with the previous visible state.
  /// Transform and opacity values interpolate; discrete frames switch at the
  /// midpoint of the transition.
  Map<String, LayerAnimation> sample() {
    final current = _playback.sample();
    final from = _blendFrom;
    if (from == null) return current;
    final progress = _blendProgress;
    if (progress >= 1) return current;
    return _blendSamples(from, current, progress);
  }

  void pause() {
    _paused = true;
  }

  void resume() {
    _paused = false;
  }

  /// Stops the active request immediately. Unless [clearQueue] is set, the next
  /// queued request starts from the default pose. The default is not blended.
  void cancelActive({bool clearQueue = false}) {
    final active = _active;
    if (active != null) {
      if (active.name == _defaultClip) {
        _playback.play(active.name, restart: true);
      } else {
        _playback.stop(active.name);
      }
      _active = null;
      _activeElapsedMs = 0;
      _firedMarkers.clear();
    }
    if (clearQueue) _queued.clear();
    _clearBlend();
    final next = _dequeue();
    if (next != null) _activate(next);
  }

  void clearQueue() {
    _queued.clear();
  }

  /// Returns to the default clip and drops all requests and pending blends.
  void clear() {
    final active = _active;
    if (active != null && active.name != _defaultClip) {
      _playback.stop(active.name);
    }
    _active = null;
    _queued.clear();
    _activeElapsedMs = 0;
    _firedMarkers.clear();
    _clearBlend();
    _paused = false;
    _playback.seek(0);
  }

  static bool _canInterrupt(
    RigStateRequest active,
    RigStateRequest incoming,
  ) =>
      incoming.priority > active.priority ||
      (active.interruptible && incoming.priority >= active.priority);

  void _activate(RigStateRequest request) {
    final previous = _active;
    final snapshot = request.transition > Duration.zero ? sample() : null;
    if (previous != null &&
        previous.name != request.name &&
        previous.name != _defaultClip) {
      _playback.stop(previous.name);
    }
    _playback.play(request.name);
    _active = request;
    _activeElapsedMs = 0;
    _firedMarkers.clear();
    _clearBlend();
    if (snapshot != null) {
      _blendFrom = snapshot;
      _blendDurationMs = request.transition.inMicroseconds / 1000;
    }
  }

  void _completeActive() {
    final finished = _active!;
    _active = null;
    _activeElapsedMs = 0;
    _firedMarkers.clear();

    if (finished.name == _defaultClip) {
      _playback.play(finished.name, restart: true);
    }

    // The completed overlay was already removed by RigPlayback. Clear any
    // entry blend before sampling the default state for the next queued
    // request.
    _clearBlend();
    final next = _dequeue();
    if (next != null) {
      _activate(next);
    }
  }

  void _enqueue(RigStateRequest request) {
    var index = _queued.length;
    for (var candidate = 0; candidate < _queued.length; candidate++) {
      if (request.priority > _queued[candidate].priority) {
        index = candidate;
        break;
      }
    }
    _queued.insert(index, request);
  }

  RigStateRequest? _dequeue() {
    if (_queued.isEmpty) return null;
    return _queued.removeAt(0);
  }

  void _clearBlend() {
    _blendFrom = null;
    _blendElapsedMs = 0;
    _blendDurationMs = 0;
  }

  double get _blendProgress {
    if (_blendFrom == null || _blendDurationMs <= 0) return 1.0;
    final raw = _blendElapsedMs / _blendDurationMs;
    return raw < 0 ? 0.0 : (raw > 1.0 ? 1.0 : raw);
  }

  Map<String, LayerAnimation> _blendSamples(
    Map<String, LayerAnimation> from,
    Map<String, LayerAnimation> to,
    double progress,
  ) {
    final ids = <String>{...from.keys, ...to.keys};
    final blended = <String, LayerAnimation>{};
    for (final id in ids) {
      final start = from[id];
      final end = to[id];
      final layer = rig.layerById(id);

      double mix(double? startValue, double? endValue, double rest) {
        final fromValue = startValue ?? rest;
        final toValue = endValue ?? rest;
        return fromValue + (toValue - fromValue) * progress;
      }

      blended[id] = LayerAnimation(
        offsetX: mix(start?.offsetX, end?.offsetX, layer?.offset.dx ?? 0),
        offsetY: mix(start?.offsetY, end?.offsetY, layer?.offset.dy ?? 0),
        rotationDegrees: mix(
          start?.rotationDegrees,
          end?.rotationDegrees,
          layer?.rotationDegrees ?? 0,
        ),
        scaleX: mix(start?.scaleX, end?.scaleX, layer?.scale.dx ?? 1),
        scaleY: mix(start?.scaleY, end?.scaleY, layer?.scale.dy ?? 1),
        opacity: mix(start?.opacity, end?.opacity, layer?.opacity ?? 1),
        frame: progress < 0.5
            ? (start?.frame ?? end?.frame)
            : (end?.frame ?? start?.frame),
      );
    }
    return blended;
  }
}

List<RigStateMarker> _orderedMarkers(List<RigStateMarker> markers) {
  final ordered = List<RigStateMarker>.of(markers);
  for (var index = 1; index < ordered.length; index++) {
    final marker = ordered[index];
    var position = index - 1;
    while (position >= 0 && ordered[position].timeMs > marker.timeMs) {
      ordered[position + 1] = ordered[position];
      position -= 1;
    }
    ordered[position + 1] = marker;
  }
  return ordered;
}
