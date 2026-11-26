import 'package:flutter/material.dart';

/// Hosts the shell-supplied companion on the Focus screen.
///
/// The Focus page does not own a renderer. When [builder] is null the stage
/// keeps its size and draws a quiet neutral surface, so layout, navigation and
/// tests work before the shell supplies the companion.
class FocusStage extends StatelessWidget {
  const FocusStage({
    required this.background,
    required this.highlight,
    required this.border,
    this.builder,
    this.radius = 28,
    super.key,
  });

  final Color background;
  final Color highlight;
  final Color border;
  final WidgetBuilder? builder;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final child = builder?.call(context);
    final corner = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corner,
        border: Border.all(color: border),
        gradient: RadialGradient(
          center: const Alignment(0, -0.15),
          radius: 0.95,
          colors: [highlight, background],
        ),
      ),
      child: ClipRRect(
        borderRadius: corner,
        child: child == null
            ? Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: border, width: 1.5),
                  ),
                ),
              )
            : Center(child: child),
      ),
    );
  }
}
