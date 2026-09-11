class TaskCompletion {
  int? id;
  int taskId; // which task this belongs to
  DateTime date; // which day this record is for
  bool isDone;
  bool isRejected; // consciously skipped, distinct from just not-yet-done
  DateTime? actualStart;
  DateTime? actualEnd;

  TaskCompletion({
    this.id,
    required this.taskId,
    required this.date,
    this.isDone = false,
    this.isRejected = false,
    this.actualStart,
    this.actualEnd,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'taskId': taskId,
      'date': _dateOnly(date),
      'isDone': isDone ? 1 : 0,
      'isRejected': isRejected ? 1 : 0,
      'actualStart': actualStart?.toIso8601String(),
      'actualEnd': actualEnd?.toIso8601String(),
    };
  }

  factory TaskCompletion.fromMap(Map<String, dynamic> map) {
    return TaskCompletion(
      id: map['id'],
      taskId: map['taskId'],
      date: DateTime.parse(map['date']),
      isDone: map['isDone'] == 1,
      isRejected: map['isRejected'] == 1,
      actualStart: map['actualStart'] != null
          ? DateTime.parse(map['actualStart'])
          : null,
      actualEnd: map['actualEnd'] != null
          ? DateTime.parse(map['actualEnd'])
          : null,
    );
  }

  // Stores only the date part (no time) so each day has exactly one record per task.
  static String _dateOnly(DateTime d) {
    return DateTime(d.year, d.month, d.day).toIso8601String();
  }
}
