import 'task.dart';

// Returns true if this task applies to the given date — shared logic used by the
// home screen, calendar view, and evaluation screen, so recurrence rules only
// live in one place.
bool isTaskRelevantForDate(Task task, DateTime targetDate) {
  final targetOnly = DateTime(
    targetDate.year,
    targetDate.month,
    targetDate.day,
  );
  final taskDateOnly = DateTime(task.date.year, task.date.month, task.date.day);

  if (task.recurrenceType == RecurrenceType.none) {
    return taskDateOnly.isAtSameMomentAs(targetOnly);
  }

  if (taskDateOnly.isAfter(targetOnly)) return false;

  if (task.recurrenceEndDate != null) {
    final endOnly = DateTime(
      task.recurrenceEndDate!.year,
      task.recurrenceEndDate!.month,
      task.recurrenceEndDate!.day,
    );
    if (targetOnly.isAfter(endOnly)) return false;
  }

  final daysSinceStart = targetOnly.difference(taskDateOnly).inDays;

  switch (task.recurrenceType) {
    case RecurrenceType.daily:
      return true;
    case RecurrenceType.weekly:
      return daysSinceStart % 7 == 0;
    case RecurrenceType.fortnightly:
      return daysSinceStart % 14 == 0;
    case RecurrenceType.monthly:
      return _matchesMonthInterval(taskDateOnly, targetOnly, 1);
    case RecurrenceType.biMonthly:
      return _matchesMonthInterval(taskDateOnly, targetOnly, 2);
    case RecurrenceType.triMonthly:
      return _matchesMonthInterval(taskDateOnly, targetOnly, 3);
    case RecurrenceType.halfYearly:
      return _matchesMonthInterval(taskDateOnly, targetOnly, 6);
    case RecurrenceType.annually:
      return taskDateOnly.month == targetOnly.month &&
          taskDateOnly.day == targetOnly.day;
    case RecurrenceType.none:
      return false;
  }
}

bool _matchesMonthInterval(
  DateTime startDate,
  DateTime targetDate,
  int intervalMonths,
) {
  if (targetDate.day != startDate.day) return false;
  final monthsSinceStart =
      (targetDate.year - startDate.year) * 12 +
      (targetDate.month - startDate.month);
  if (monthsSinceStart < 0) return false;
  return monthsSinceStart % intervalMonths == 0;
}
