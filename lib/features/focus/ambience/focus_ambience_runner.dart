import 'dart:async';

import 'package:flutter/material.dart';

import 'focus_ambience_controller.dart';
import 'focus_ambience_engine.dart';
import 'focus_ambience_player.dart';
import 'focus_ambience_preferences.dart';

/// Wires Focus ambience to one Focus surface without changing its layout.
///
/// Mount this above the Focus page inside the shell's Focus tab. The runner
/// watches the tab's [TickerMode], the route observer and the app lifecycle, so
/// the loop stops when Focus is hidden, covered by Settings, backgrounded or
/// left, and starts again only after [active] is true and the surface is
/// visible. Accessibility is unchanged: the runner only adds audio state.
class FocusAmbienceRunner extends StatefulWidget {
  const FocusAmbienceRunner({
    required this.preferences,
    required this.active,
    required this.child,
    this.routeObserver,
    this.engine,
    super.key,
  });

  /// The saved choice. The runner adopts changes in place.
  final FocusAmbiencePreferences preferences;

  /// True while a Focus session is running on the Focus surface.
  final bool active;

  final Widget child;

  /// The shell's route observer, used to stop while another route covers Focus.
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;

  /// Test seam. The runner owns and releases a player when this is null.
  final FocusAmbienceEngine? engine;

  @override
  State<FocusAmbienceRunner> createState() => _FocusAmbienceRunnerState();
}

class _FocusAmbienceRunnerState extends State<FocusAmbienceRunner>
    with WidgetsBindingObserver, RouteAware {
  late final FocusAmbienceEngine _engine =
      widget.engine ?? FocusAmbiencePlayer();
  late final bool _ownsEngine;
  late final FocusAmbienceController _controller = FocusAmbienceController(
    engine: _engine,
    preferences: widget.preferences,
    // Seeded from the binding, so a runner created while the app is already
    // backgrounded never assumes a resume that did not happen.
    initialLifecycle:
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
  );

  FocusAmbiencePlayer? _player;
  RouteObserver<ModalRoute<dynamic>>? _observer;
  ModalRoute<dynamic>? _route;
  bool _covered = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ownsEngine = widget.engine == null;
    WidgetsBinding.instance.addObserver(this);
    if (_engine case final FocusAmbiencePlayer player) {
      _player = player;
      player.onHeadphonesConnected =
          () => unawaited(_controller.setHeadphonesConnected(true));
      player.onHeadphonesDisconnected =
          () => unawaited(_controller.setHeadphonesConnected(false));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = widget.routeObserver;
    if (observer != _observer) {
      _observer?.unsubscribe(this);
      _observer = observer;
      _route = null;
    }
    final route = ModalRoute.of<dynamic>(context);
    if (route != _route) {
      _observer?.unsubscribe(this);
      _route = route;
      if (route != null) _observer?.subscribe(this, route);
    }
    _updateVisibility();
  }

  @override
  void didUpdateWidget(covariant FocusAmbienceRunner oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      oldWidget.engine == widget.engine,
      'FocusAmbienceRunner does not replace its engine.',
    );
    if (oldWidget.preferences != widget.preferences) {
      unawaited(_controller.apply(widget.preferences));
    }
    if (oldWidget.routeObserver != widget.routeObserver) {
      oldWidget.routeObserver?.unsubscribe(this);
      _observer = widget.routeObserver;
      final route = _route;
      if (route != null) _observer?.subscribe(this, route);
    }
    if (oldWidget.active != widget.active) _updateVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_controller.setLifecycle(state));
  }

  @override
  void didPushNext() {
    _covered = true;
    _updateVisibility();
  }

  @override
  void didPopNext() {
    _covered = false;
    _updateVisibility();
  }

  void _updateVisibility() {
    // Read the inherited ticker mode unconditionally. Inside the && chain the
    // lookup is skipped whenever Focus is already inactive, which leaves the
    // State with no dependency and misses the next tab switch back.
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final visible =
        widget.active &&
        !_covered &&
        tickerEnabled &&
        (_route?.isCurrent ?? true);
    if (visible == _visible) return;
    _visible = visible;
    unawaited(_controller.setVisible(visible));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observer?.unsubscribe(this);
    final player = _player;
    player?.onHeadphonesConnected = null;
    player?.onHeadphonesDisconnected = null;
    final disposed = _controller.dispose();
    if (_ownsEngine && player != null) {
      unawaited(disposed.whenComplete(() {
        player.detach();
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
