import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/storage/session_record.dart';
import '../../design/companion_theme.dart';
import 'insights_summary.dart';

/// Session summaries and history for the Insights destination.
///
/// The page is content-only so the navigation shell can own the [Scaffold],
/// app bar and bottom navigation.
class InsightsPage extends StatefulWidget {
  const InsightsPage({required this.sessions, super.key});

  final List<SessionRecord> sessions;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> with WidgetsBindingObserver {
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchDate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _watchDate();
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _midnight?.cancel();
    }
  }

  void _watchDate() {
    _midnight?.cancel();
    final now = DateTime.now();
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

  @override
  Widget build(BuildContext context) {
    final summary = summarizeSessions(widget.sessions, now: DateTime.now());
    return SafeArea(
      child: summary.isEmpty
          ? const _FirstRunEmptyState()
          : _InsightsContent(summary: summary),
    );
  }
}

class _InsightsContent extends StatelessWidget {
  const _InsightsContent({required this.summary});

  final InsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CompanionTheme.pageInset,
            CompanionTheme.pageInset,
            CompanionTheme.pageInset,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TodayCard(
                  today: summary.today,
                  totals: summary.todayTotals,
                ),
                const SizedBox(height: 12),
                _PeriodSummaryCard(summary: summary),
                const SizedBox(height: 12),
                _SevenDayCard(
                  days: summary.lastSevenDays,
                  totals: summary.lastSevenDaysTotals,
                ),
                const SizedBox(height: 24),
                _HistoryHeader(count: summary.history.length),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CompanionTheme.pageInset,
            0,
            CompanionTheme.pageInset,
            24,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SessionTile(
                session: summary.history[index],
              ),
              childCount: summary.history.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today, required this.totals});

  final CalendarDay today;
  final SessionTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Today',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    localizations.formatMediumDate(today.start),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              children: [
                Text(
                  _durationLabel(totals.focused),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabularFigures,
                  ),
                ),
                Text(
                  'focused',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              totals.sessions == 0
                  ? 'No sessions yet today'
                  : _completionDetail(totals),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSummaryCard extends StatelessWidget {
  const _PeriodSummaryCard({required this.summary});

  final InsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            _SummaryRow(
              icon: Icons.date_range_outlined,
              label: 'This week',
              value: _durationLabel(summary.weekTotals.focused),
              detail: _completionDetail(summary.weekTotals),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _SummaryRow(
              icon: Icons.calendar_month_outlined,
              label: 'This month',
              value: _durationLabel(summary.monthTotals.focused),
              detail: _completionDetail(summary.monthTotals),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _SummaryRow(
              icon: Icons.av_timer_outlined,
              label: 'Average session',
              value: _durationLabel(summary.averageFocused),
              detail: summary.allTimeTotals.sessions == 0
                  ? 'No saved sessions'
                  : 'Across ${_countLabel(summary.allTimeTotals.sessions)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: _tabularFigures,
              ),
            ),
          ),
        ],
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
                      'Last 7 days',
                      style: theme.textTheme.titleMedium,
                    ),
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
      child: SizedBox(
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

class _ActivityBarFill extends StatelessWidget {
  const _ActivityBarFill({required this.day});

  final DayActivity day;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = day.completedFocused.inMilliseconds;
    final uncompleted = day.uncompletedFocused.inMilliseconds;
    if (completed == 0 && uncompleted == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (uncompleted > 0)
          Expanded(
            flex: uncompleted,
            child: ColoredBox(color: colors.secondary),
          ),
        if (completed > 0)
          Expanded(
            flex: completed,
            child: ColoredBox(color: colors.primary),
          ),
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
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text('History', style: theme.textTheme.titleMedium),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _countLabel(count),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final SessionRecord session;

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
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showSessionDetails(context, session),
        leading: Icon(
          session.completed
              ? Icons.check_circle_outline
              : Icons.timer_off_outlined,
          color: session.completed ? colors.primary : colors.onSurfaceVariant,
        ),
        title: Text(
          '${_durationLabel(session.actual)} focused',
          style: theme.textTheme.bodyLarge,
        ),
        subtitle: Text(
          '$date · $timeRange\n${_sessionStatus(session)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}

void _showSessionDetails(BuildContext context, SessionRecord session) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _SessionDetailsSheet(session: session),
  );
}

class _SessionDetailsSheet extends StatelessWidget {
  const _SessionDetailsSheet({required this.session});

  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final started = session.startedAt.toLocal();
    final finished = session.finishedAt.toLocal();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  session.completed
                      ? Icons.check_circle
                      : Icons.timer_off_outlined,
                  color: session.completed
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.completed
                        ? 'Completed session'
                        : 'Session not completed',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
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
            _DetailRow(
              label: 'Result',
              value: _sessionStatus(session),
            ),
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
            width: 88,
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

class _FirstRunEmptyState extends StatelessWidget {
  const _FirstRunEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
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
            ],
          ),
        ),
      ),
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
  final noun = totals.sessions == 1 ? 'session' : 'sessions';
  return '${totals.completed} of ${totals.sessions} $noun completed';
}

String _sessionStatus(SessionRecord session) {
  if (session.completed) return 'Completed';
  final remaining = session.intended - session.actual;
  if (remaining > Duration.zero) {
    return 'Ended ${_durationLabel(remaining)} early';
  }
  return 'Not completed';
}
