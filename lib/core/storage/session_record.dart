class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.intended,
    required this.actual,
    required this.completed,
  });

  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Duration intended;
  final Duration actual;
  final bool completed;

  Map<String, Object> toJson() => {
    'id': id,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'finishedAt': finishedAt.millisecondsSinceEpoch,
    'intendedMs': intended.inMilliseconds,
    'actualMs': actual.inMilliseconds,
    'completed': completed,
  };

  static SessionRecord fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'startedAt': final int startedAt,
      'finishedAt': final int finishedAt,
      'intendedMs': final int intended,
      'actualMs': final int actual,
      'completed': final bool completed,
    } when id.isNotEmpty &&
        id.length <= 128 &&
        finishedAt >= startedAt &&
        intended > 0 &&
        intended <= const Duration(days: 1).inMilliseconds &&
        actual >= 0 &&
        actual <= intended &&
        (!completed || actual == intended)) {
      return SessionRecord(
        id: id,
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true),
        finishedAt: DateTime.fromMillisecondsSinceEpoch(finishedAt, isUtc: true),
        intended: Duration(milliseconds: intended),
        actual: Duration(milliseconds: actual),
        completed: completed,
      );
    }
    throw const FormatException('Invalid focus session.');
  }
}
