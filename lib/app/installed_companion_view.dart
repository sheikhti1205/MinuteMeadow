import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../companion_engine/animation/state_controller.dart';
import '../companion_engine/debug/geometric_rig.dart';
import '../companion_engine/render/affine2.dart';
import '../companion_engine/render/atlas_cache.dart';
import '../companion_engine/render/companion_pose.dart';
import '../companion_engine/render/sprite_painter.dart';
import '../companion_engine/rig/rig_model.dart';
import '../companion_engine/scene/companion_scene.dart';
import '../core/notifications/pack_audio.dart';
import '../features/companion/companion_library.dart';
import '../features/companion/pack_manifest.dart';
import 'companion_stage_layout.dart';

/// Renders one companion stage from the shared compositor and scene.
///
/// Pass an installed [pack] to draw it, or leave [pack] null:
/// - with [useDevelopmentFixture] the geometric development rig is drawn
///   through the same renderer, so layout and interactions can be checked
///   before finished pet art exists;
/// - without it the view reserves [stageHeight] and shows an intentional
///   empty stage instead of a loading state or a fake companion.
class InstalledCompanionView extends StatefulWidget {
  const InstalledCompanionView({
    required this.pack,
    required this.lowPower,
    required this.sound,
    required this.ambientClip,
    this.useDevelopmentFixture = false,
    this.stageHeight = 200,
    this.showInteractionControls = true,
    this.debugStage,
    super.key,
  })  : assert(stageHeight > 0),
        assert(pack == null || debugStage == null);

  final InstalledPack? pack;
  final bool lowPower;
  final bool sound;
  final foundation.ValueListenable<String?> ambientClip;

  /// Draws [GeometricRigFixture] through the production compositor when
  /// [pack] is null. This is a development actor, never production pet art.
  final bool useDevelopmentFixture;

  /// Height reserved for the stage in logical pixels.
  final double stageHeight;

  /// Shows the compact pet and ball controls below the stage. Pointer
  /// interaction on the stage remains available either way.
  ///
  /// Hidden controls also make the view exactly [stageHeight] tall: the
  /// confirmation is exposed as a live region on the stage instead of an
  /// inline notice, so hosts that give this view a fixed square cannot clip it.
  final bool showInteractionControls;

  /// A prebuilt rig and atlas for widget tests.
  ///
  /// Tests create it with [GeometricRigFixture.create] inside
  /// `WidgetTester.runAsync`, so the stage needs no engine work inside the
  /// fake-async test zone. Production callers leave this null.
  @foundation.visibleForTesting
  final GeometricRigBundle? debugStage;

  @override
  State<InstalledCompanionView> createState() => _InstalledCompanionViewState();
}

class _InstalledCompanionViewState extends State<InstalledCompanionView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  _CompanionStage? _stage;
  Duration? _lastTick;
  bool _failed = false;
  bool _loading = true;
  bool _dependenciesReady = false;
  bool _active = true;
  bool _reduceMotion = false;
  bool _ballInPlay = false;
  final _interactionClock = Stopwatch()..start();
  Duration? _lastPet;
  Duration? _lastSound;
  String? _notice;
  String? _ambientClip;
  bool _playedOneShotAmbient = false;
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
    _dependenciesReady = true;
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
    final packChanged = oldWidget.pack != widget.pack;
    final fixtureChanged =
        widget.pack == null &&
        oldWidget.useDevelopmentFixture != widget.useDevelopmentFixture;
    final debugChanged = oldWidget.debugStage != widget.debugStage;
    if (packChanged || fixtureChanged || debugChanged) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.ambientClip.removeListener(_applyAmbientClip);
    _ticker.dispose();
    _stage?.dispose();
    if (_lastSound != null) unawaited(PackAudio.stop());
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    final pack = widget.pack;
    final prebuilt = widget.debugStage;
    final useFixture =
        pack == null && prebuilt == null && widget.useDevelopmentFixture;
    if (pack == null && prebuilt == null && !useFixture) {
      final previous = _stage;
      if (mounted && revision == _loadRevision) {
        // The first load runs from initState, where the pending build already
        // covers these field changes, so only rebuild when mounted and ready.
        if (_dependenciesReady) {
          setState(_showEmptyStage);
        } else {
          _showEmptyStage();
        }
      }
      previous?.dispose();
      if (_dependenciesReady) _syncTicker();
      return;
    }

    // Tests hand over an already-decoded stage so no engine future has to
    // complete inside the fake-async widget-test zone.
    if (pack == null && prebuilt != null) {
      final cache = AtlasCache()
        ..put(prebuilt.atlasId, prebuilt.atlasImage.clone());
      final next = _CompanionStage(prebuilt.rig, cache);
      if (!mounted || revision != _loadRevision) {
        next.dispose();
        return;
      }
      final previous = _stage;
      _installStage(next);
      previous?.dispose();
      _applyAmbientClip();
      if (_dependenciesReady) _syncTicker();
      return;
    }

    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final cache = AtlasCache();
    try {
      final CompanionRig rig;
      if (pack != null) {
        rig = _convertRig(pack);
        for (final id in rig.atlases.keys) {
          cache.put(id, await AtlasCache.decode(pack.assets[id]!.bytes));
          if (!mounted || revision != _loadRevision) {
            cache.dispose();
            return;
          }
        }
      } else {
        final bundle = await GeometricRigFixture.create();
        if (!mounted || revision != _loadRevision) {
          bundle.atlasImage.dispose();
          return;
        }
        cache.put(bundle.atlasId, bundle.atlasImage);
        rig = bundle.rig;
      }
      final next = _CompanionStage(rig, cache);
      final previous = _stage;
      if (!mounted || revision != _loadRevision) {
        next.dispose();
        return;
      }
      _installStage(next);
      previous?.dispose();
      _applyAmbientClip();
      if (_dependenciesReady) _syncTicker();
    } on Exception {
      cache.dispose();
      if (mounted && revision == _loadRevision) {
        setState(() {
          _failed = true;
          _loading = false;
        });
        if (_dependenciesReady) _syncTicker();
      }
    }
  }

  void _installStage(_CompanionStage next) {
    void apply() {
      _stage = next;
      _resetStageState();
    }

    if (_dependenciesReady) {
      setState(apply);
    } else {
      // The first load runs from initState; the pending build covers it.
      apply();
    }
  }

  void _resetStageState() {
    _failed = false;
    _loading = false;
    _notice = null;
    _ballInPlay = false;
    _ambientClip = null;
    _playedOneShotAmbient = false;
  }

  void _showEmptyStage() {
    _stage = null;
    _resetStageState();
  }

  void _applyAmbientClip() {
    final stage = _stage;
    if (stage == null) return;
    final previous = _ambientClip;
    final next = widget.ambientClip.value;
    if (previous == next) return;
    if (previous != null && stage.animator.activeName == previous) {
      stage.animator.cancelActive();
    }
    _ambientClip = next;
    _playedOneShotAmbient = false;
    _startAmbientIfIdle(stage);
    stage.repaint();
    if (_dependenciesReady) _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) return;
    final stage = _stage;
    final shouldRun = !_failed &&
        _active &&
        TickerMode.valuesOf(context).enabled &&
        stage != null &&
        (_ballInPlay ||
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
    stage.scene.advance(passed);
    var clipCompleted = false;
    if (!_reduceMotion) {
      for (final event in stage.animator.advance(passed.inMicroseconds / 1000)) {
        switch (event) {
          case RigStateMarkerEvent(:final marker):
            _playSound(marker.name);
          case RigStateCompletionEvent():
            clipCompleted = true;
        }
      }
      if (clipCompleted) _startAmbientIfIdle(stage);
    }
    var ballEnded = false;
    for (final event in stage.scene.takeEvents()) {
      if (event.type == CompanionSceneEventType.ballCaught) {
        _play(stage, 'catch');
        _playSound('catch');
      } else if (event.type == CompanionSceneEventType.ballReturned ||
          event.type == CompanionSceneEventType.ballMissed) {
        ballEnded = true;
        _playSound(
          event.type == CompanionSceneEventType.ballReturned
              ? 'ball_returned'
              : 'ball_missed',
        );
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
        _playSound('pet');
      }
    }
    stage.repaint();
    if (ballEnded || clipCompleted || !stage.hasAnimation) _syncTicker();
  }

  void _play(_CompanionStage stage, String clip) {
    if (_reduceMotion || stage.animator.activeName == clip ||
        stage.animator.queuedRequests.any((request) => request.name == clip)) {
      return;
    }
    // The stage may still show its previous rig while a new pack loads.
    if (stage.rig.clipById(clip) == null) return;
    final pack = widget.pack;
    if (pack != null) {
      for (final spec in pack.manifest.clips) {
        if (spec.id != clip) continue;
        final state = spec.state;
        stage.animator.request(
          clip,
          priority:
              state?.priority ?? (clip == 'catch' ? 10 : clip == 'pet' ? 5 : 0),
          interruptible: state?.interruptible ?? true,
          transition: state == null
              ? null
              : Duration(milliseconds: state.transitionMs),
          markers: [
            for (final marker in spec.events)
              RigStateMarker(name: marker.id, timeMs: marker.timeMs),
          ],
        );
        return;
      }
      return;
    }
    stage.animator.request(
      clip,
      priority: clip == 'catch' ? 10 : clip == 'pet' ? 5 : 0,
      interruptible: true,
    );
  }

  void _startAmbientIfIdle(_CompanionStage stage) {
    final clip = _ambientClip;
    if (clip == null || _playedOneShotAmbient || stage.animator.hasActiveRequest) {
      return;
    }
    _play(stage, clip);
    if (stage.animator.activeName == clip &&
        stage.rig.clipById(clip)?.loop == false) {
      _playedOneShotAmbient = true;
    }
  }

  void _playSound(String event) {
    final pack = widget.pack;
    if (!widget.sound || !_active || pack == null) return;
    for (final sound in pack.manifest.sounds) {
      if (sound.event != event) continue;
      final asset = pack.assets[sound.asset];
      final now = _interactionClock.elapsed;
      final last = _lastSound;
      if (asset != null &&
          (last == null || now - last >= const Duration(milliseconds: 180))) {
        _lastSound = now;
        unawaited(PackAudio.play(asset.bytes, sound.volume));
      }
      return;
    }
  }

  void _pet(Offset? point) {
    final stage = _stage;
    final now = _interactionClock.elapsed;
    final last = _lastPet;
    if (last != null && now - last < const Duration(milliseconds: 220)) return;
    if (stage == null ||
        !stage.scene.startPet(point ?? stage.scene.companionCenter)) {
      return;
    }
    _lastPet = now;
    if (point == null || _reduceMotion) {
      _play(stage, 'pet');
      _playSound('pet');
      stage.scene.takeEvents();
      stage.scene.endPet();
      stage.repaint();
    }
    setState(
      () => _notice = 'Petted ${widget.pack?.manifest.name ?? 'companion'}',
    );
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
    _playSound('ball_thrown');
    stage.repaint();
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    if (_failed) return _failureStage();
    if (stage == null && _loading) return _loadingStage(context);
    if (stage == null) return _emptyStage(context);
    return _buildStage(context, stage);
  }

  Widget _buildStage(BuildContext context, _CompanionStage stage) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scene = stage.scene;
    final name = widget.pack?.manifest.name ?? 'Companion';
    final notice = _notice;
    final showControls = widget.showInteractionControls;
    // Without inline controls the host gives this view a fixed square. Fold
    // the confirmation into the stage's live region so it never adds a
    // variable-height layout item that large text or long names can clip.
    final stageLabel = showControls || notice == null
        ? '$name stage'
        : '$name stage. $notice';
    final stageBox = SizedBox(
      height: widget.stageHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = CompanionStageLayout.fit(
            viewport: constraints.biggest,
            field: scene.field,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
          if (layout.scale <= 0) return const SizedBox.shrink();
          return Stack(
            children: [
              Positioned(
                left: layout.offset.dx,
                top: layout.offset.dy,
                width: layout.size.width,
                height: layout.size.height,
                child: RepaintBoundary(
                  child: Semantics(
                    key: const ValueKey('companion-stage-semantics'),
                    container: true,
                    label: stageLabel,
                    liveRegion: !showControls,
                    child: GestureDetector(
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (scene.hitTestCompanion(
                          details.localPosition / layout.scale,
                        )) {
                          _pet(null);
                        }
                      },
                      onPanStart: (details) =>
                          _pet(details.localPosition / layout.scale),
                      onPanUpdate: (details) {
                        scene.updatePet(details.localPosition / layout.scale);
                        if (!scene.isPetting) _syncTicker();
                      },
                      onPanEnd: (_) => _endPet(),
                      onPanCancel: _endPet,
                      child: CustomPaint(
                        key: const ValueKey('companion-stage-canvas'),
                        size: layout.size,
                        painter: _StagePainter(stage, colors, layout),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (!showControls) return stageBox;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stageBox,
        const SizedBox(height: 4),
        Wrap(
          key: const ValueKey('companion-interaction-controls'),
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            _StageAction(
              icon: Icons.pets_outlined,
              label: 'Pet',
              onPressed: _ballInPlay ? null : () => _pet(null),
            ),
            _StageAction(
              icon: Icons.sports_baseball,
              label: 'Throw ball',
              onPressed: _ballInPlay ? null : _throwBall,
            ),
          ],
        ),
        if (notice != null) ...[
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(
              notice,
              key: const ValueKey('companion-stage-notice'),
              textAlign: TextAlign.center,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _loadingStage(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('companion-loading-stage'),
      height: widget.stageHeight,
      width: double.infinity,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: 'Loading companion',
          excludeSemantics: true,
          child: Text(
            'Loading companion…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyStage(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      key: const ValueKey('companion-empty-stage'),
      height: widget.stageHeight,
      width: double.infinity,
      child: Semantics(
        container: true,
        label:
            'Companion stage. No companion installed. '
            'Install a companion to see it here.',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.pets_outlined,
                    size: 28,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Companion stage',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Install a companion to see it here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _failureStage() {
    return SizedBox(
      height: widget.stageHeight,
      width: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not draw this companion.'),
            TextButton(onPressed: _load, child: const Text('Retry preview')),
          ],
        ),
      ),
    );
  }
}

class _StageAction extends StatelessWidget {
  const _StageAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Keep the visual compact through padding and icon size, but never undercut
    // the padded 48dp touch target the shared theme expects.
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _CompanionStage extends ChangeNotifier {
  _CompanionStage(this.rig, this.atlas)
    : animator = RigStateController(rig),
      scene = CompanionScene(
        field: Size(
          math.max(144, rig.canvasWidth + 80).toDouble(),
          math.max(96, rig.canvasHeight + 31).toDouble(),
        ),
        companionSize: rig.canvasSize,
      );

  final CompanionRig rig;
  final AtlasCache atlas;
  final RigStateController animator;
  final CompanionScene scene;

  bool get hasAnimation => animator.isAnimating || animator.hasBaseMotion;

  void repaint() => notifyListeners();

  @override
  void dispose() {
    atlas.dispose();
    super.dispose();
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.stage, this.colors, this.layout) : super(repaint: stage);

  final _CompanionStage stage;
  final ColorScheme colors;
  final CompanionStageLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final scene = stage.scene;
    final scale = layout.scale;
    if (scale <= 0) return;
    canvas.save();
    canvas.scale(scale);
    final actor = scene.companionRect;
    final left = layout.align(actor.left);
    final top = layout.align(actor.top);
    final shadow = Paint()
      ..color = colors.outline.withValues(alpha: 0.28)
      ..isAntiAlias = false;
    canvas.drawRect(
      Rect.fromLTWH(
        left + actor.width / 4,
        top + actor.height - 1,
        actor.width / 2,
        3,
      ),
      shadow,
    );
    final facing = scene.facing;
    final root = Affine2.translation(
      facing < 0 ? left + actor.width : left,
      top,
    ) * Affine2.scale(facing, 1);
    // SpritePainter samples with FilterQuality.none; the layout keeps the
    // actor origin on the physical-pixel grid for integer source scale.
    SpritePainter(
      pose: buildCompanionPose(
        stage.rig,
        animations: stage.animator.sample(),
        rootTransform: root,
      ),
      atlas: stage.atlas,
      sceneSize: scene.field,
      background: Colors.transparent,
    ).paint(canvas, scene.field);
    if (scene.ballPhase != BallPhase.none) {
      final offset = scene.ballPosition;
      final x = layout.align(offset.dx);
      final y = layout.align(offset.dy);
      final ball = Paint()
        ..color = colors.primary
        ..isAntiAlias = false;
      canvas.drawRect(Rect.fromLTWH(x - 4, y - 3, 8, 6), ball);
      canvas.drawRect(Rect.fromLTWH(x - 3, y - 4, 6, 8), ball);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StagePainter oldDelegate) =>
      oldDelegate.stage != stage ||
      oldDelegate.colors != colors ||
      oldDelegate.layout != layout;
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
    final tracksByLayer = <String, List<PropertyTrack>>{};
    for (final track in clip.tracks) {
      tracksByLayer.putIfAbsent(track.layer, () => []).add(PropertyTrack(
        property: LayerProperty.values.byName(track.property.name),
        keyframes: [
          for (final frame in track.keyframes)
            Keyframe(
              timeMs: frame.timeMs,
              value: frame.value,
              easing: KeyframeEasing.values.byName(frame.easing.name),
            ),
        ],
      ));
    }
    clips[clip.id] = ClipDefinition(
      id: clip.id,
      durationMs: clip.timelineDurationMs,
      loop: clip.loop,
      layers: [
        for (final id in {...framesByLayer.keys, ...tracksByLayer.keys})
          LayerClip(
            layerId: id,
            frames: switch (framesByLayer[id]) {
              final frames? => FrameTrack(
                frames: frames,
                frameDurationMs: clip.frameDurationMs,
                loop: clip.loop,
              ),
              null => null,
            },
            tracks: tracksByLayer[id] ?? const [],
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
            parent: layer.pose.parent,
            offset: switch (layer.pose.offset) {
              final point? => Offset(point.x, point.y),
              null when layer.pose.parent != null => Offset.zero,
              null => Offset(
                ((manifest.canvasWidth - frame.width) / 2).roundToDouble(),
                (manifest.canvasHeight - frame.height).toDouble(),
              ),
            },
            pivot: switch (layer.pose.pivot) {
              final point? => Offset(point.x, point.y),
              null => Offset.zero,
            },
            rotationDegrees: layer.pose.rotationDegrees,
            scale: Offset(layer.pose.scale.x, layer.pose.scale.y),
            opacity: layer.pose.opacity,
            visible: layer.pose.visible,
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
