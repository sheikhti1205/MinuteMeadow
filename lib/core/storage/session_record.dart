/// Optional text a person can attach to a recorded focus session.
///
/// Labels and notes are descriptive only. They never change the recorded
/// start, finish, intended or focused durations, or whether the session
/// completed.
class SessionDetails {
  const SessionDetails({this.label, this.note});

  static const maxLabelLength = 80;
  static const maxNoteLength = 500;

  static const empty = SessionDetails();

  /// Trims input and treats blank text as absent.
  factory SessionDetails.fromInput({Object? label, Object? note}) =>
      SessionDetails(
        label: _optionalText(label, maxLabelLength),
        note: _optionalText(note, maxNoteLength),
      );

  final String? label;
  final String? note;

  bool get isEmpty => label == null && note == null;

  Map<String, Object> toJson() => {
    if (label != null) 'label': label!,
    if (note != null) 'note': note!,
  };

  @override
  bool operator ==(Object other) =>
      other is SessionDetails && other.label == label && other.note == note;

  @override
  int get hashCode => Object.hash(label, note);

  @override
  String toString() =>
      'SessionDetails(label: ${label != null}, note: ${note != null})';
}

String? _optionalText(Object? value, int limit) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid session details.');
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > limit) {
    throw const FormatException('Session details are too long.');
  }
  return trimmed;
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.intended,
    required this.actual,
    required this.completed,
    this.label,
    this.note,
  });

  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Duration intended;
  final Duration actual;
  final bool completed;
  final String? label;
  final String? note;

  SessionDetails get details => SessionDetails(label: label, note: note);

  /// Returns a copy with only the descriptive text replaced.
  ///
  /// Timestamps, durations and the completion outcome are carried over
  /// unchanged so editing a label or note cannot rewrite recorded history.
  SessionRecord withDetails(SessionDetails details) => SessionRecord(
    id: id,
    startedAt: startedAt,
    finishedAt: finishedAt,
    intended: intended,
    actual: actual,
    completed: completed,
    label: details.label,
    note: details.note,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'finishedAt': finishedAt.millisecondsSinceEpoch,
    'intendedMs': intended.inMilliseconds,
    'actualMs': actual.inMilliseconds,
    'completed': completed,
    if (label != null) 'label': label!,
    if (note != null) 'note': note!,
  };

  static SessionRecord fromJson(Object? json) {
    if (json case final Map<String, Object?> map) {
      if (map case {
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
        final details = SessionDetails.fromInput(
          label: map['label'],
          note: map['note'],
        );
        return SessionRecord(
          id: id,
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            startedAt,
            isUtc: true,
          ),
          finishedAt: DateTime.fromMillisecondsSinceEpoch(
            finishedAt,
            isUtc: true,
          ),
          intended: Duration(milliseconds: intended),
          actual: Duration(milliseconds: actual),
          completed: completed,
          label: details.label,
          note: details.note,
        );
      }
    }
    throw const FormatException('Invalid focus session.');
  }
}
