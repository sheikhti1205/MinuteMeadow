import 'package:flutter/material.dart';

import 'focus_engine.dart';

/// Wall time one finite focus plan needs when every block runs to its end,
/// including the final long break that closes the plan.
Duration focusPlanTotal(FocusSettings settings) {
  final sessions = settings.sessionsPerCycle;
  final shortBreaks = sessions > 1 ? sessions - 1 : 0;
  return Duration(
    minutes:
        sessions * settings.focusMinutes +
        shortBreaks * settings.shortBreakMinutes +
        settings.longBreakMinutes,
  );
}

/// Compact duration copy for a plan total, such as `2h 10m` or `45m`.
String formatFocusPlanTotal(Duration duration) {
  final minutes = (duration.inSeconds / Duration.secondsPerMinute).round();
  final hours = minutes ~/ Duration.minutesPerHour;
  final rest = minutes % Duration.minutesPerHour;
  if (hours == 0) return '${rest}m';
  if (rest == 0) return '${hours}h';
  return '${hours}h ${rest}m';
}

/// The parts of a plan in the units a person configured: how many blocks, the
/// focus duration of each block, and the two break lengths. Kept as one short
/// line that wraps at its separators on a narrow phone.
String _planBreakdown(FocusSettings settings) {
  final blocks = settings.sessionsPerCycle;
  final focus = _formatMinutes(settings.focusMinutes);
  final count = blocks == 1 ? '1 block' : '$blocks blocks';
  final each = blocks == 1 ? '' : ' each';
  final parts = <String>[
    count,
    '$focus focus$each',
    if (blocks > 1)
      '${_formatMinutes(settings.shortBreakMinutes)} short break',
    '${_formatMinutes(settings.longBreakMinutes)} long break',
  ];
  return parts.join(' · ');
}

String _formatMinutes(int minutes) =>
    formatFocusPlanTotal(Duration(minutes: minutes));

/// The advancing finish estimate for the setup surface.
///
/// The finish time is recomputed from the engine clock on each build, so the
/// page's low-frequency ticker keeps it current. The manual assumption is
/// stated only when phase changes wait for a person, which is the honest case;
/// with auto-advance the plan runs straight through.
class FocusPlanPreview extends StatelessWidget {
  const FocusPlanPreview({
    required this.settings,
    required this.doneAt,
    required this.autoAdvance,
    super.key,
  });

  final FocusSettings settings;
  final DateTime doneAt;
  final bool autoAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(doneAt.toLocal()),
    );
    final total = formatFocusPlanTotal(focusPlanTotal(settings));
    final assumption = autoAdvance
        ? ''
        : ', assuming no waiting between blocks';
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.35,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Done around $time · $total in all$assumption',
          textAlign: TextAlign.center,
          style: style,
        ),
        const SizedBox(height: 4),
        Text(
          _planBreakdown(settings),
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }
}

/// The active plan's whole block sequence: every focus block, the short break
/// between blocks, and the long break that closes the plan.
///
/// Passed, current and upcoming segments differ in height and outline as well
/// as colour, and the caption names the current block, so the current state is
/// readable without colour and while paused.
class FocusPlanTimeline extends StatelessWidget {
  const FocusPlanTimeline({
    required this.target,
    required this.completed,
    required this.phase,
    required this.settings,
    required this.active,
    this.paused = false,
    super.key,
  });

  final int target;
  final int completed;
  final FocusPhase phase;
  final FocusSettings settings;
  final bool active;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocks = target < 1 ? 1 : target;
    final done = completed < 0
        ? 0
        : (completed > blocks ? blocks : completed);
    final current = active ? _currentSegment(blocks, done) : null;
    final passedUntil = current ?? 2 * done;
    final shortBreaks = blocks - 1;
    final spokenBreaks = shortBreaks == 0
        ? 'no short breaks'
        : (shortBreaks == 1 ? '1 short break' : '$shortBreaks short breaks');
    final spokenBlocks = blocks == 1 ? '1 focus block' : '$blocks focus blocks';
    final caption = _caption(blocks, done);

    return Semantics(
      container: true,
      label:
          'Plan timeline: $spokenBlocks with $spokenBreaks and a final long '
          'break. $caption.',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var segment = 0; segment < blocks * 2; segment++) ...[
                  if (segment > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: _segmentMinutes(segment, blocks),
                    child: Container(
                      height: segment == current
                          ? 9
                          : (segment.isOdd ? 3 : 5),
                      decoration: BoxDecoration(
                        color: segment < passedUntil
                            ? scheme.onSurface
                            : (segment == current
                                  ? scheme.primary
                                  : scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                        border: segment == current
                            ? Border.all(color: scheme.onSurface)
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Zero-based segment that is running: even indexes are focus blocks, odd
  /// indexes are the break after the preceding block, and the last segment is
  /// the plan's long break.
  int _currentSegment(int blocks, int done) {
    if (phase == FocusPhase.focus) {
      final block = done < blocks ? done : blocks - 1;
      return block * 2;
    }
    final after = done < 1 ? 1 : (done > blocks ? blocks : done);
    return after >= blocks ? blocks * 2 - 1 : after * 2 - 1;
  }

  /// Duration of one segment, so the row's widths follow the configured plan
  /// instead of guessing equal blocks.
  int _segmentMinutes(int segment, int blocks) {
    final segmentPhase = !segment.isOdd
        ? FocusPhase.focus
        : (segment == blocks * 2 - 1
              ? FocusPhase.longBreak
              : FocusPhase.shortBreak);
    final minutes = settings.durationFor(segmentPhase).inMinutes;
    return minutes < 1 ? 1 : minutes;
  }

  String _caption(int blocks, int done) {
    if (!active) {
      return blocks == 1 ? '1 focus block' : '$blocks focus blocks';
    }
    if (phase == FocusPhase.focus) {
      final block = done < blocks ? done + 1 : blocks;
      final current = 'Block $block of $blocks · Focus';
      return paused ? 'Paused · $current' : current;
    }
    final after = done < 1 ? 1 : (done > blocks ? blocks : done);
    final name = phase == FocusPhase.longBreak ? 'Long break' : 'Short break';
    final current = '$name after block $after of $blocks';
    return paused ? 'Paused · $current' : current;
  }
}
