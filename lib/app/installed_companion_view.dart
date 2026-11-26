import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../companion_engine/animation/rig_playback.dart';
import '../companion_engine/render/affine2.dart';
import '../companion_engine/render/atlas_cache.dart';
import '../companion_engine/render/companion_pose.dart';
import '../companion_engine/render/sprite_painter.dart';
import '../companion_engine/rig/rig_model.dart';
import '../companion_engine/scene/companion_scene.dart';
import '../features/companion/companion_library.dart';
import '../features/companion/pack_manifest.dart';

class InstalledCompanionView extends StatefulWidget {
  const InstalledCompanionView({
    required this.pack,
    required this.lowPower,
    required this.ambientClip,
    super.key,
  });

  final InstalledPack pack;
  final bool lowPower;
  final foundation.ValueListenable<String?> ambientClip;

  @override
  State<InstalledCompanionView> createState() => _InstalledCompanionViewState();
}

class _InstalledCompanionViewState extends State<InstalledCompanionView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  _CompanionStage? _stage;
  Duration? _lastTick;
  bool _failed = false;
  bool _active = true;
  bool _reduceMotion = false;
  bool _ballInPlay = false;
  String? _notice;
  String? _ambientClip;
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.ambientClip.addListener(_applyAmbientClip);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant InstalledCompanionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ambientClip != widget.ambientClip) {
      oldWidget.ambientClip.removeListener(_applyAmbientClip);
      widget.ambientClip.addListener(_applyAmbientClip);
      _applyAmbientClip();
    }
    if (oldWidget.pack != widget.pack) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.ambientClip.removeListener(_applyAmbientClip);
    _ticker.dispose();
    _stage?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    final pack = widget.pack;
    final cache = AtlasCache();
    try {
      final rig = _convertRig(pack);
      for (final id in rig.atlases.keys) {
        cache.put(id, await AtlasCache.decode(pack.assets[id]!.bytes));
        if (!mounted || revision != _loadRevision) {
          cache.dispose();
          return;
        }
      }
      final next = _CompanionStage(rig, cache);
      final previous = _stage;
      setState(() {
        _stage = next;
        _failed = false;
        _notice = null;
        _ballInPlay = false;
        _ambientClip = null;
      });
      previous?.dispose();
      _applyAmbientClip();
      _syncTicker();
    } on Exception {
      cache.dispose();
      if (mounted && revision == _loadRevision) setState(() => _failed = true);
    }
  }

  void _applyAmbientClip() {
    final stage = _stage;
    if (stage == null) return;
    final previous = _ambientClip;
    final next = widget.ambientClip.value;
    if (previous == next) return;
    if (previous != null) stage.playback.stop(previous);
    _ambientClip = next;
    if (next != null && stage.rig.clips.containsKey(next)) {
      stage.playback.play(next);
    }
    stage.repaint();
    _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) return;
    final stage = _stage;
    final shouldRun = _active && TickerMode.valuesOf(context).enabled &&
        stage != null && (_ballInPlay ||
            (!_reduceMotion && (stage.scene.isPetting || stage.hasAnimation)));
    if (shouldRun && !_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
      _lastTick = null;
    }
  }

  void _tick(Duration elapsed) {
    final stage = _stage;
    if (stage == null) return;
    final last = _lastTick;
    if (last == null) {
      _lastTick = elapsed;
      return;
    }
    final passed = elapsed - last;
    if (widget.lowPower && passed < const Duration(milliseconds: 32)) return;
    _lastTick = elapsed;
    final delta = passed > stage.scene.maxStep ? stage.scene.maxStep : passed;
    stage.scene.advance(delta);
    final clipCompleted = !_reduceMotion &&
        stage.playback.advance(delta.inMicroseconds / 1000).any((event) => event.completed);
    var ballEnded = false;
    for (final event in stage.scene.takeEvents()) {
      if (event.type == CompanionSceneEventType.ballCaught) {
        _play(stage, 'catch');
      } else if (event.type == CompanionSceneEventType.ballReturned ||
          event.type == CompanionSceneEventType.ballMissed) {
        ballEnded = true;
        if (mounted) {
          setState(() {
            _ballInPlay = false;
            _notice = event.type == CompanionSceneEventType.ballReturned
                ? 'Ball returned'
                : 'Ball missed';
          });
        }
      } else if (event.type == CompanionSceneEventType.pet) {
        _play(stage, 'pet');
      }
    }
    stage.repaint();
    if (ballEnded || clipCompleted) _syncTicker();
  }

  void _play(_CompanionStage stage, String clip) {
    if (!_reduceMotion && stage.rig.clips.containsKey(clip)) {
      stage.playback.play(clip);
    }
  }

  void _pet(Offset? point) {
    final stage = _stage;
    if (stage == null || !stage.scene.startPet(point ?? stage.scene.companionCenter)) {
      return;
    }
    if (point == null || _reduceMotion) {
      _play(stage, 'pet');
      stage.scene.takeEvents();
      stage.scene.endPet();
      stage.repaint();
    }
    setState(() => _notice = 'Petted ${widget.pack.manifest.name}');
    _syncTicker();
  }

  void _endPet() {
    _stage?.scene.endPet();
    _syncTicker();
  }

  void _throwBall() {
    final stage = _stage;
    if (stage == null || !stage.scene.throwBall()) return;
    setState(() {
      _ballInPlay = true;
      _notice = 'Ball thrown';
    });
    stage.repaint();
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Column(
        children: [
          const Text('Could not draw this companion.'),
          TextButton(onPressed: _load, child: const Text('Retry preview')),
        ],
      );
    }
    final stage = _stage;
    if (stage == null) return const Center(child: Text('Loading companion…'));
    final colors = Theme.of(context).colorScheme;
    final scene = stage.scene;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 200,
          child: LayoutBuilder(builder: (context, constraints) {
            final ratio = MediaQuery.devicePixelRatioOf(context);
            final fit = math.min(
              constraints.maxWidth * ratio / scene.field.width,
              constraints.maxHeight * ratio / scene.field.height,
            );
            if (fit <= 0) return const SizedBox.shrink();
            final scale = (fit >= 1 ? fit.floorToDouble() : fit) / ratio;
            return Center(
              child: RepaintBoundary(
                child: GestureDetector(
                  excludeFromSemantics: true,
                  onTapUp: (details) {
                    if (scene.hitTestCompanion(details.localPosition / scale)) _pet(null);
                  },
                  onPanStart: (details) => _pet(details.localPosition / scale),
                  onPanUpdate: (details) {
                    scene.updatePet(details.localPosition / scale);
                    if (!scene.isPetting) _syncTicker();
                  },
                  onPanEnd: (_) => _endPet(),
                  onPanCancel: _endPet,
                  child: CustomPaint(
                    size: Size(scene.field.width * scale, scene.field.height * scale),
                    painter: _StagePainter(stage, colors, scale),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _ballInPlay ? null : () => _pet(null),
              child: const Text('Pet'),
            ),
            OutlinedButton(
              onPressed: _ballInPlay ? null : _throwBall,
              child: const Text('Throw ball'),
            ),
          ],
        ),
        if (_notice case final notice?)
          Semantics(liveRegion: true, child: Text(notice, textAlign: TextAlign.center)),
      ],
    );
  }
}

class _CompanionStage extends ChangeNotifier {
  _CompanionStage(this.rig, this.atlas)
    : playback = RigPlayback(rig: rig),
      scene = CompanionScene(
        field: Size(
          math.max(144, rig.canvasWidth + 80).toDouble(),
          math.max(96, rig.canvasHeight + 31).toDouble(),
        ),
        companionSize: rig.canvasSize,
      );

  final CompanionRig rig;
  final AtlasCache atlas;
  final RigPlayback playback;
  final CompanionScene scene;

  bool get hasAnimation => rig.clips.values.any((clip) {
    final position = playback.timeOf(clip.id);
    return position != null &&
        (clip.loop || position < clip.durationMs) &&
        clip.layers.any((layer) =>
            (layer.frames?.frames.length ?? 0) > 1 || layer.tracks.isNotEmpty);
  });

  void repaint() => notifyListeners();

  @override
  void dispose() {
    atlas.dispose();
    super.dispose();
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.stage, this.colors, this.scale) : super(repaint: stage);

  final _CompanionStage stage;
  final ColorScheme colors;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final scene = stage.scene;
    canvas.save();
    canvas.scale(scale);
    final actor = scene.companionRect;
    final shadow = Paint()
      ..color = colors.outline.withValues(alpha: 0.28)
      ..isAntiAlias = false;
    canvas.drawRect(
      Rect.fromLTWH(actor.left + actor.width / 4, actor.bottom - 1, actor.width / 2, 3),
      shadow,
    );
    final facing = scene.facing;
    final root = Affine2.translation(
      (facing < 0 ? actor.right : actor.left).roundToDouble(),
      actor.top.roundToDouble(),
    ) * Affine2.scale(facing, 1);
    SpritePainter(
      pose: buildCompanionPose(
        stage.rig,
        animations: stage.playback.sample(),
        rootTransform: root,
      ),
      atlas: stage.atlas,
      sceneSize: scene.field,
      background: Colors.transparent,
    ).paint(canvas, scene.field);
    if (scene.ballPhase != BallPhase.none) {
      final offset = scene.ballPosition;
      final x = offset.dx.roundToDouble();
      final y = offset.dy.roundToDouble();
      final ball = Paint()..color = colors.primary;
      canvas.drawRect(Rect.fromLTWH(x - 4, y - 3, 8, 6), ball);
      canvas.drawRect(Rect.fromLTWH(x - 3, y - 4, 6, 8), ball);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StagePainter oldDelegate) =>
      oldDelegate.stage != stage ||
      oldDelegate.colors != colors ||
      oldDelegate.scale != scale;
}

CompanionRig _convertRig(InstalledPack pack) {
  final manifest = pack.manifest;
  final atlases = <String, AtlasDefinition>{};
  final rest = <String, SpriteRegion>{};
  final clips = <String, ClipDefinition>{};
  for (final clip in manifest.clips) {
    final framesByLayer = <String, List<SpriteRegion>>{};
    for (final frame in clip.frames) {
      final asset = pack.assets[frame.asset]!;
      final region = _region(frame);
      atlases.putIfAbsent(
        frame.asset,
        () => AtlasDefinition(id: frame.asset, width: asset.width, height: asset.height),
      );
      rest.putIfAbsent(frame.layer, () => region);
      framesByLayer.putIfAbsent(frame.layer, () => []).add(region);
    }
    final frameMs = (1000 / clip.fps).round();
    final count = framesByLayer.values.fold<int>(1, (max, frames) => math.max(max, frames.length));
    clips[clip.id] = ClipDefinition(
      id: clip.id,
      durationMs: frameMs * count,
      loop: clip.loop,
      layers: [
        for (final entry in framesByLayer.entries)
          LayerClip(
            layerId: entry.key,
            frames: FrameTrack(
              frames: entry.value,
              frameDurationMs: frameMs,
              loop: clip.loop,
            ),
          ),
      ],
    );
  }
  final ordered = [...manifest.layers]..sort((left, right) => left.z.compareTo(right.z));
  return CompanionRig(
    canvasWidth: manifest.canvasWidth,
    canvasHeight: manifest.canvasHeight,
    atlases: atlases,
    layers: [
      for (final layer in ordered)
        if (rest[layer.id] case final frame?)
          LayerDefinition(
            id: layer.id,
            defaultFrame: frame,
            offset: Offset(
              ((manifest.canvasWidth - frame.width) / 2).roundToDouble(),
              (manifest.canvasHeight - frame.height).toDouble(),
            ),
          ),
    ],
    clips: clips,
    defaultClip: clips.containsKey('idle') ? 'idle' : clips.keys.first,
  );
}

SpriteRegion _region(PackFrame frame) => SpriteRegion(
  atlas: frame.asset,
  x: frame.rect.x,
  y: frame.rect.y,
  width: frame.rect.width,
  height: frame.rect.height,
);
