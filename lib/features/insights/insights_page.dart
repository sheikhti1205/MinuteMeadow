import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/storage/session_record.dart';
import '../../design/companion_theme.dart';
import 'insights_summary.dart';

/// Persists only the descriptive text for one saved session.
typedef SessionDetailsUpdater =
    Future<void> Function(String id, SessionDetails details);

/// Deletes the selected saved sessions in one transaction.
typedef SessionsDeleter = Future<void> Function(Set<String> ids);

/// Session summaries and history for the Insights destination.
///
/// The page is content-only so the navigation shell can own the [Scaffold],
/// app bar and bottom navigation. Persistence stays with the shell: the page
/// reads [sessions] and reports edits or deletions through the typed
/// callbacks. Omitting the callbacks leaves the overview and history readable
/// but read-only. When a callback completes, the shell should re-read the
/// database and rebuild with fresh [sessions] so every summary agrees with
/// what was saved.
class InsightsPage extends StatefulWidget {
  const InsightsPage({
    required this.sessions,
    this.onUpdateDetails,
    this.onDeleteSessions,
    this.now,
    this.localDay,
    super.key,
  });

  final List<SessionRecord> sessions;
  final SessionDetailsUpdater? onUpdateDetails;
  final SessionsDeleter? onDeleteSessions;

  /// Injectable clock for tests; production uses the device time.
  final DateTime Function()? now;

  /// Injectable local-day projection for tests; production uses local time.
  final CalendarDay Function(DateTime instant)? localDay;

  static const historyButtonKey = ValueKey('insights-history');
  static const emptyStateKey = ValueKey('insights-empty');

  static ValueKey<String> periodKey(InsightsPeriod period) =>
      ValueKey('insights-period-${period.name}');

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage>
    with WidgetsBindingObserver {
  Timer? _midnight;
  late List<SessionRecord> _sessions;
  InsightsPeriod _period = InsightsPeriod.today;

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessions;
    WidgetsBinding.instance.addObserver(this);
    _watchDate();
  }

  @override
  void didUpdateWidget(covariant InsightsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _sessions = widget.sessions;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _watchDate();
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _midnight?.cancel();
    }
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  void _watchDate() {
    _midnight?.cancel();
    final now = _now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _watchDate();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => InsightsHistoryPage(
          sessions: _sessions,
          onUpdateDetails: widget.onUpdateDetails,
          onDeleteSessions: widget.onDeleteSessions,
          onSessionsChanged: (sessions) {
            if (mounted) setState(() => _sessions = sessions);
          },
          now: widget.now,
          localDay: widget.localDay,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = summarizeSessions(
      _sessions,
      now: _now(),
      localDay: widget.localDay,
    );
    if (summary.isEmpty) {
      return const SafeArea(child: _FirstRunEmptyState());
    }
    final periodSessions = sessionsInPeriod(
      _sessions,
      period: _period,
      today: summary.today,
      localDay: widget.localDay,
    );
    final totals = SessionTotals.of(periodSessions);
    final recent = periodSessions.take(4).toList(growable: false);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          CompanionTheme.pageInset,
          CompanionTheme.pageInset,
          CompanionTheme.pageInset,
          24,
        ),
        children: [
          _PeriodTabs(
            selected: _period,
            onChanged: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: 12),
          _StatsGrid(totals: totals),
          const SizedBox(height: 12),
          _SevenDayCard(
            days: summary.lastSevenDays,
            totals: summary.lastSevenDaysTotals,
          ),
          const SizedBox(height: 12),
          const _LeaderboardTeaser(),
          const SizedBox(height: 24),
          _RecentHeader(onSeeAll: _openHistory),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            _EmptyPeriodCard(period: _period)
          else
            for (final session in recent)
              _SessionTile(session: session, onTap: _openHistory),
        ],
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.selected, required this.onChanged});

  final InsightsPeriod selected;
  final ValueChanged<InsightsPeriod> onChanged;

  static const _entries = <(InsightsPeriod, String)>[
    (InsightsPeriod.today, 'Today'),
    (InsightsPeriod.week, 'Week'),
    (InsightsPeriod.month, 'Month'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final (period, label) in _entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: selected == period,
                child: Material(
                  color: selected == period
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    key: InsightsPage.periodKey(period),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onChanged(period),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: selected == period
                                ? colors.onPrimary
                                : colors.onSurfaceVariant,
                            fontWeight: selected == period
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.totals});

  final SessionTotals totals;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.timer_outlined,
                  label: 'Focused',
                  value: _durationLabel(totals.focused),
                  detail: totals.sessions == 1
                      ? '1 session'
                      : '${totals.sessions} sessions',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.list_alt,
                  label: 'Sessions',
                  value: '${totals.sessions}',
                  detail: totals.sessions == 1 ? 'session' : 'sessions',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle_outline,
                  label: 'Completion',
                  value: totals.sessions == 0
                      ? '—'
                      : '${totals.completionPercent}%',
                  detail: totals.sessions == 0
                      ? 'Nothing recorded'
                      : '${totals.completed} completed',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.av_timer_outlined,
                  label: 'Average',
                  value: _durationLabel(totals.averageFocused),
                  detail: totals.sessions == 0 ? 'No sessions' : 'Per session',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: _tabularFigures,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Recent sessions',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        TextButton(
          key: InsightsPage.historyButtonKey,
          onPressed: onSeeAll,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('See all'),
              SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyPeriodCard extends StatelessWidget {
  const _EmptyPeriodCard({required this.period});

  final InsightsPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = switch (period) {
      InsightsPeriod.today => 'today',
      InsightsPeriod.week => 'this week',
      InsightsPeriod.month => 'this month',
      InsightsPeriod.all => 'yet',
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.timer_off_outlined, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No sessions $label.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SevenDayCard extends StatelessWidget {
  const _SevenDayCard({required this.days, required this.totals});

  final List<DayActivity> days;
  final SessionTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxFocused = days.fold<int>(
      0,
      (value, day) => math.max(value, day.totals.focused.inMilliseconds),
    );
    final summaryLine = totals.sessions == 0
        ? 'No focus sessions in the last 7 days'
        : '${_durationLabel(totals.focused)} focused · '
              '${_completionDetail(totals)}';
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Focus time',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                Text(
                  'Last 7 days',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ActivityChart(
              days: days,
              totals: totals,
              maxFocused: maxFocused,
            ),
            const SizedBox(height: 12),
            Text(
              summaryLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            const _ChartLegend(),
          ],
        ),
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({
    required this.days,
    required this.totals,
    required this.maxFocused,
  });

  final List<DayActivity> days;
  final SessionTotals totals;
  final int maxFocused;

  static const double _height = 132;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Semantics(
      container: true,
      label: _semanticsLabel(localizations),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelSize =
              Theme.of(context).textTheme.labelSmall?.fontSize ?? 11;
          final minimumBarWidth =
              MediaQuery.textScalerOf(context).scale(labelSize) * 3 + 6;
          if (constraints.maxWidth < minimumBarWidth * days.length) {
            return Column(
              children: [
                for (final day in days)
                  _WideActivityBar(day: day, maxFocused: maxFocused),
              ],
            );
          }
          return SizedBox(
            height: _height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _ActivityBar(day: day, maxFocused: maxFocused),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _semanticsLabel(MaterialLocalizations localizations) {
    final buffer = StringBuffer('Focus activity for the last seven days. ');
    for (final day in days) {
      final date = localizations.formatFullDate(day.day.start);
      final dayTotals = day.totals;
      if (dayTotals.sessions == 0) {
        buffer.write('$date: no sessions. ');
      } else {
        buffer.write(
          '$date: ${_countLabel(dayTotals.sessions)}, '
          '${dayTotals.completed} completed, '
          '${_durationLabel(dayTotals.focused)} focused. ',
        );
      }
    }
    if (totals.sessions == 0) {
      buffer.write('No sessions were recorded.');
    } else {
      buffer.write(
        'Total: ${_durationLabel(totals.focused)} focused, '
        '${_completionDetail(totals)}.',
      );
    }
    return buffer.toString();
  }
}

class _ActivityBar extends StatelessWidget {
  const _ActivityBar({required this.day, required this.maxFocused});

  final DayActivity day;
  final int maxFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final focused = day.totals.focused.inMilliseconds;
    final ratio = maxFocused == 0 ? 0.0 : focused / maxFocused;
    final heightFactor = focused == 0
        ? 0.0
        : math.min(1.0, math.max(0.04, ratio));
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 0.68,
                  heightFactor: heightFactor,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _ActivityBarFill(day: day),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _weekdayLabels[day.day.weekday - 1],
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _WideActivityBar extends StatelessWidget {
  const _WideActivityBar({required this.day, required this.maxFocused});

  final DayActivity day;
  final int maxFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = day.totals.focused.inMilliseconds;
    final fraction = maxFocused == 0 ? 0.0 : focused / maxFocused;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Text(
                _weekdayLabels[day.day.weekday - 1],
                style: theme.textTheme.labelSmall,
              ),
              Text(
                _durationLabel(day.totals.focused),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            height: 6,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: _ActivityBarFill(day: day, direction: Axis.horizontal),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityBarFill extends StatelessWidget {
  const _ActivityBarFill({required this.day, this.direction = Axis.vertical});

  final DayActivity day;
  final Axis direction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = day.completedFocused.inMilliseconds;
    final uncompleted = day.uncompletedFocused.inMilliseconds;
    if (completed == 0 && uncompleted == 0) {
      return const SizedBox.shrink();
    }
    return Flex(
      direction: direction,
      children: [
        if (uncompleted > 0)
          Expanded(flex: uncompleted, child: ColoredBox(color: colors.secondary)),
        if (completed > 0)
          Expanded(flex: completed, child: ColoredBox(color: colors.primary)),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _LegendItem(color: colors.primary, label: 'Completed'),
        _LegendItem(color: colors.secondary, label: 'Not completed'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
    this.checkKey,
    super.key,
  });

  final SessionRecord session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;
  final Key? checkKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final started = session.startedAt.toLocal();
    final finished = session.finishedAt.toLocal();
    final date = localizations.formatMediumDate(finished);
    final timeRange =
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(started))} – '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(finished))}';
    final label = session.label;
    final note = session.note;
    final title = label ?? '${_durationLabel(session.actual)} focused';
    final subtitle = [
      '$date · $timeRange',
      if (label != null)
        '${_durationLabel(session.actual)} · ${_sessionStatus(session)}'
      else
        _sessionStatus(session),
      if (note != null) note,
    ].join('\n');
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        selected: selected,
        leading: selectionMode
            ? Checkbox(
                key: checkKey,
                value: selected,
                onChanged: onSelectedChanged,
              )
            : CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Icon(
                  session.completed
                      ? Icons.check_rounded
                      : Icons.timer_off_outlined,
                  size: 20,
                ),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Text(
          subtitle,
          maxLines: note != null ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        isThreeLine: note != null,
        trailing: selectionMode
            ? null
            : const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}

enum _DetailAction { edit, delete }

class _SessionDetailsSheet extends StatelessWidget {
  const _SessionDetailsSheet({
    required this.session,
    this.canEdit = false,
    this.canDelete = false,
  });

  final SessionRecord session;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final started = session.startedAt.toLocal();
    final finished = session.finishedAt.toLocal();
    final label = session.label;
    final note = session.note;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: Icon(
                    session.completed
                        ? Icons.check_rounded
                        : Icons.timer_off_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label ?? (session.completed
                            ? 'Completed session'
                            : 'Session not completed'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sessionStatus(session),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(note, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Started',
              value:
                  '${localizations.formatMediumDate(started)} · '
                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(started))}',
            ),
            _DetailRow(
              label: 'Finished',
              value:
                  '${localizations.formatMediumDate(finished)} · '
                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(finished))}',
            ),
            _DetailRow(
              label: 'Intended',
              value: _durationLabel(session.intended),
            ),
            _DetailRow(
              label: 'Focused',
              value: _durationLabel(session.actual),
            ),
            const SizedBox(height: 8),
            _DurationComparison(session: session),
            if (canEdit || canDelete) ...[
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canDelete)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _DetailAction.delete),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  if (canEdit)
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _DetailAction.edit),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit label or note'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _DurationComparison extends StatelessWidget {
  const _DurationComparison({required this.session});

  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final intended = session.intended.inMilliseconds;
    final ratio = intended == 0
        ? 0.0
        : math.min(1.0, session.actual.inMilliseconds / intended);
    return Semantics(
      label:
          '${_durationLabel(session.actual)} focused of '
          '${_durationLabel(session.intended)} intended',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Intended vs focused',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '${_durationLabel(session.actual)} of '
                '${_durationLabel(session.intended)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
              color: session.completed ? colors.primary : colors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstRunEmptyState extends StatelessWidget {
  const _FirstRunEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      key: InsightsPage.emptyStateKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CompanionTheme.pageInset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.insights_outlined,
                  size: 32,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No sessions yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Finish a focus session and your daily, weekly and monthly '
                'summaries will appear here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              const _LeaderboardTeaser(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks the leaderboard as planned without offering anything to operate.
class _LeaderboardTeaser extends StatelessWidget {
  const _LeaderboardTeaser();

  static const _description =
      'Compare focus time with others once it is available.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Semantics(
        container: true,
        label: 'Leaderboard. Coming soon. $_description',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.leaderboard_outlined,
                  size: 18,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Leaderboard',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Coming soon',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full history management, opened from the overview.
class InsightsHistoryPage extends StatefulWidget {
  const InsightsHistoryPage({
    required this.sessions,
    this.onUpdateDetails,
    this.onDeleteSessions,
    this.onSessionsChanged,
    this.now,
    this.localDay,
    super.key,
  });

  final List<SessionRecord> sessions;
  final SessionDetailsUpdater? onUpdateDetails;
  final SessionsDeleter? onDeleteSessions;
  final ValueChanged<List<SessionRecord>>? onSessionsChanged;
  final DateTime Function()? now;
  final CalendarDay Function(DateTime instant)? localDay;

  static const selectButtonKey = ValueKey('history-select');
  static const dateFilterKey = ValueKey('history-date-filter');
  static const outcomeFilterKey = ValueKey('history-outcome-filter');
  static const deleteSelectedKey = ValueKey('history-delete-selected');
  static const confirmDeleteKey = ValueKey('history-confirm-delete');
  static const editorLabelKey = ValueKey('history-label-field');
  static const editorNoteKey = ValueKey('history-note-field');
  static const editorSaveKey = ValueKey('history-editor-save');
  static const errorBannerKey = ValueKey('history-error');

  static ValueKey<String> sessionRowKey(String id) =>
      ValueKey('history-session-$id');

  static ValueKey<String> sessionCheckKey(String id) =>
      ValueKey('history-check-$id');

  @override
  State<InsightsHistoryPage> createState() => _InsightsHistoryPageState();
}

enum _DateFilterPreset { all, today, last7, last30, custom }

class _InsightsHistoryPageState extends State<InsightsHistoryPage> {
  late List<SessionRecord> _sessions;
  _DateFilterPreset _datePreset = _DateFilterPreset.all;
  CalendarDay? _customFrom;
  CalendarDay? _customTo;
  SessionOutcomeFilter _outcome = SessionOutcomeFilter.all;
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessions;
  }

  @override
  void didUpdateWidget(covariant InsightsHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sessions, widget.sessions)) {
      _sessions = widget.sessions;
      _selected.removeWhere(
        (id) => !_sessions.any((session) => session.id == id),
      );
    }
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  CalendarDay get _today =>
      (widget.localDay ?? CalendarDay.fromLocal)(_now());

  CalendarDay? get _from => switch (_datePreset) {
    _DateFilterPreset.all => null,
    _DateFilterPreset.today => _today,
    _DateFilterPreset.last7 => _today.addDays(-6),
    _DateFilterPreset.last30 => _today.addDays(-29),
    _DateFilterPreset.custom => _customFrom,
  };

  CalendarDay? get _to => switch (_datePreset) {
    _DateFilterPreset.all => null,
    _DateFilterPreset.today => _today,
    _DateFilterPreset.last7 => _today,
    _DateFilterPreset.last30 => _today,
    _DateFilterPreset.custom => _customTo,
  };

  bool get _canDelete => widget.onDeleteSessions != null;

  bool get _canEdit => widget.onUpdateDetails != null;

  Future<void> _pickDatePreset(_DateFilterPreset preset) async {
    if (preset == _DateFilterPreset.custom) {
      await _pickCustomRange();
      return;
    }
    if (!mounted) return;
    setState(() {
      _datePreset = preset;
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = _now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!.start, end: _customTo!.start)
          : null,
      helpText: 'Filter sessions by date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _datePreset = _DateFilterPreset.custom;
      _customFrom = CalendarDay.fromLocal(picked.start);
      _customTo = CalendarDay.fromLocal(picked.end);
      _selected.clear();
      _selecting = false;
    });
  }

  void _setOutcome(SessionOutcomeFilter outcome) {
    setState(() {
      _outcome = outcome;
      _selected.clear();
      _selecting = false;
    });
  }

  void _clearFilters() {
    setState(() {
      _datePreset = _DateFilterPreset.all;
      _customFrom = null;
      _customTo = null;
      _outcome = SessionOutcomeFilter.all;
      _selected.clear();
      _selecting = false;
    });
  }

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _openDetails(SessionRecord session) async {
    final action = await showModalBottomSheet<_DetailAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SessionDetailsSheet(
        session: session,
        canEdit: _canEdit,
        canDelete: _canDelete,
      ),
    );
    if (!mounted || action == null) return;
    if (action == _DetailAction.edit) {
      await _editSession(session);
    } else if (action == _DetailAction.delete) {
      await _confirmDelete({session.id});
    }
  }

  Future<void> _editSession(SessionRecord session) async {
    final updater = widget.onUpdateDetails;
    if (updater == null || _busy) return;
    final details = await showDialog<SessionDetails>(
      context: context,
      builder: (context) => _SessionEditorDialog(session: session),
    );
    if (details == null || !mounted) return;
    await _mutate(() async {
      await updater(session.id, details);
      if (!mounted) return;
      setState(() {
        _sessions = [
          for (final item in _sessions)
            if (item.id == session.id) item.withDetails(details) else item,
        ];
      });
      widget.onSessionsChanged?.call(_sessions);
    }, success: 'Session updated.');
  }

  Future<void> _confirmDelete(Set<String> ids) async {
    final deleter = widget.onDeleteSessions;
    if (deleter == null || ids.isEmpty || _busy) return;
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(count == 1 ? 'Delete 1 session?' : 'Delete $count sessions?'),
        content: Text(
          count == 1
              ? 'This removes the recorded session from your summaries. '
                    'It cannot be undone.'
              : 'This removes $count recorded sessions from your summaries. '
                    'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: InsightsHistoryPage.confirmDeleteKey,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              count == 1 ? 'Delete 1 session' : 'Delete $count sessions',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = Set<String>.of(ids);
    await _mutate(() async {
      await deleter(removed);
      if (!mounted) return;
      setState(() {
        _sessions = _sessions
            .where((session) => !removed.contains(session.id))
            .toList(growable: false);
        _selected.removeAll(removed);
        if (_selected.isEmpty) _selecting = false;
      });
      widget.onSessionsChanged?.call(_sessions);
    }, success: count == 1 ? 'Session deleted.' : '$count sessions deleted.');
  }

  Future<void> _mutate(
    Future<void> Function() action, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not update saved sessions. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = newestFirst(
      filterSessions(
        _sessions,
        from: _from,
        to: _to,
        outcome: _outcome,
        localDay: widget.localDay,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (_canDelete && _sessions.isNotEmpty)
            TextButton(
              key: InsightsHistoryPage.selectButtonKey,
              onPressed: _busy ? null : _toggleSelecting,
              child: Text(_selecting ? 'Done' : 'Select'),
            ),
        ],
      ),
      body: Column(
        children: [
          _HistoryFilterBar(
            datePreset: _datePreset,
            customFrom: _customFrom,
            customTo: _customTo,
            outcome: _outcome,
            onDateSelected: _pickDatePreset,
            onOutcomeSelected: _setOutcome,
          ),
          if (_error case final error?)
            _ErrorBanner(
              key: InsightsHistoryPage.errorBannerKey,
              message: error,
              onDismiss: () => setState(() => _error = null),
            ),
          if (_busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Saving changes',
              minHeight: 2,
            ),
          Expanded(
            child: visible.isEmpty
                ? _HistoryEmptyState(
                    hasSessions: _sessions.isNotEmpty,
                    onClearFilters: _clearFilters,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      CompanionTheme.pageInset,
                      8,
                      CompanionTheme.pageInset,
                      24,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final session = visible[index];
                      return _SessionTile(
                        key: InsightsHistoryPage.sessionRowKey(session.id),
                        session: session,
                        selectionMode: _selecting,
                        selected: _selected.contains(session.id),
                        checkKey: InsightsHistoryPage.sessionCheckKey(
                          session.id,
                        ),
                        onSelectedChanged: (value) {
                          if (value != null) _toggleSelected(session.id);
                        },
                        onTap: _selecting
                            ? () => _toggleSelected(session.id)
                            : () => _openDetails(session),
                        onLongPress: _canDelete
                            ? () {
                                if (!_selecting) {
                                  setState(() {
                                    _selecting = true;
                                    _selected.add(session.id);
                                  });
                                } else {
                                  _toggleSelected(session.id);
                                }
                              }
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selecting && _canDelete
          ? _SelectionBar(
              count: _selected.length,
              busy: _busy,
              onDelete: _selected.isEmpty
                  ? null
                  : () => _confirmDelete(Set<String>.of(_selected)),
            )
          : null,
    );
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.datePreset,
    required this.customFrom,
    required this.customTo,
    required this.outcome,
    required this.onDateSelected,
    required this.onOutcomeSelected,
  });

  final _DateFilterPreset datePreset;
  final CalendarDay? customFrom;
  final CalendarDay? customTo;
  final SessionOutcomeFilter outcome;
  final ValueChanged<_DateFilterPreset> onDateSelected;
  final ValueChanged<SessionOutcomeFilter> onOutcomeSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final dateLabel = switch (datePreset) {
      _DateFilterPreset.all => 'All dates',
      _DateFilterPreset.today => 'Today',
      _DateFilterPreset.last7 => 'Last 7 days',
      _DateFilterPreset.last30 => 'Last 30 days',
      _DateFilterPreset.custom =>
        customFrom == null || customTo == null
            ? 'Custom range'
            : '${localizations.formatShortMonthDay(customFrom!.start)} – '
                  '${localizations.formatShortMonthDay(customTo!.start)}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CompanionTheme.pageInset,
        8,
        CompanionTheme.pageInset,
        8,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PopupMenuButton<_DateFilterPreset>(
            key: InsightsHistoryPage.dateFilterKey,
            tooltip: 'Filter by date',
            onSelected: onDateSelected,
            itemBuilder: (context) => [
              for (final preset in _DateFilterPreset.values)
                PopupMenuItem(
                  value: preset,
                  child: Text(_datePresetMenuLabel(preset)),
                ),
            ],
            child: _FilterChip(
              icon: Icons.date_range_outlined,
              label: dateLabel,
            ),
          ),
          PopupMenuButton<SessionOutcomeFilter>(
            key: InsightsHistoryPage.outcomeFilterKey,
            tooltip: 'Filter by outcome',
            onSelected: onOutcomeSelected,
            itemBuilder: (context) => [
              for (final filter in SessionOutcomeFilter.values)
                PopupMenuItem(
                  value: filter,
                  child: Text(_outcomeLabel(filter)),
                ),
            ],
            child: _FilterChip(
              icon: Icons.flag_outlined,
              label: _outcomeLabel(outcome),
            ),
          ),
        ],
      ),
    );
  }

  String _datePresetMenuLabel(_DateFilterPreset preset) => switch (preset) {
    _DateFilterPreset.all => 'All dates',
    _DateFilterPreset.today => 'Today',
    _DateFilterPreset.last7 => 'Last 7 days',
    _DateFilterPreset.last30 => 'Last 30 days',
    _DateFilterPreset.custom => 'Custom range…',
  };
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onDelete,
  });

  final int count;
  final bool busy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count == 1 ? '1 selected' : '$count selected',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              FilledButton.icon(
                key: InsightsHistoryPage.deleteSelectedKey,
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(count == 1 ? 'Delete 1' : 'Delete $count'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({
    required this.hasSessions,
    required this.onClearFilters,
  });

  final bool hasSessions;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CompanionTheme.pageInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSessions
                  ? Icons.search_off
                  : Icons.history,
              size: 40,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              hasSessions
                  ? 'No sessions match these filters'
                  : 'No sessions yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasSessions
                  ? 'Adjust the date or outcome filter to see saved sessions.'
                  : 'Finish a focus session and it will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (hasSessions) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onClearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        CompanionTheme.pageInset,
        0,
        CompanionTheme.pageInset,
        8,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 18, color: colors.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class _SessionEditorDialog extends StatefulWidget {
  const _SessionEditorDialog({required this.session});

  final SessionRecord session;

  @override
  State<_SessionEditorDialog> createState() => _SessionEditorDialogState();
}

class _SessionEditorDialogState extends State<_SessionEditorDialog> {
  late final _label = TextEditingController(text: widget.session.label ?? '');
  late final _note = TextEditingController(text: widget.session.note ?? '');
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final details = SessionDetails.fromInput(
        label: _label.text,
        note: _note.text,
      );
      Navigator.pop(context, details);
    } on FormatException {
      setState(
        () => _error =
            'Keep the label to ${SessionDetails.maxLabelLength} characters '
            'and the note to ${SessionDetails.maxNoteLength}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AlertDialog(
      scrollable: true,
      title: const Text('Edit session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Label and note only. Recorded times and result stay unchanged.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: InsightsHistoryPage.editorLabelKey,
            controller: _label,
            maxLength: SessionDetails.maxLabelLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'What did you work on?',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: InsightsHistoryPage.editorNoteKey,
            controller: _note,
            minLines: 3,
            maxLines: 5,
            maxLength: SessionDetails.maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Anything worth remembering?',
              alignLabelWithHint: true,
            ),
          ),
          if (_error case final error?)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: InsightsHistoryPage.editorSaveKey,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

const _tabularFigures = <ui.FontFeature>[ui.FontFeature.tabularFigures()];

const _weekdayLabels = <String>['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

String _durationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes <= 0) {
    return duration > Duration.zero ? '<1 min' : '0 min';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

String _countLabel(int count) =>
    count == 1 ? '1 session' : '$count sessions';

String _completionDetail(SessionTotals totals) {
  if (totals.sessions == 0) return 'No sessions yet';
  return '${totals.completed} of ${totals.sessions} '
      '${totals.sessions == 1 ? 'session' : 'sessions'} completed';
}

String _outcomeLabel(SessionOutcomeFilter filter) => switch (filter) {
  SessionOutcomeFilter.all => 'All outcomes',
  SessionOutcomeFilter.completed => 'Completed',
  SessionOutcomeFilter.notCompleted => 'Not completed',
};

String _sessionStatus(SessionRecord session) {
  if (session.completed) return 'Completed';
  final remaining = session.intended - session.actual;
  if (remaining > Duration.zero) {
    return 'Ended ${_durationLabel(remaining)} early';
  }
  return 'Not completed';
}
