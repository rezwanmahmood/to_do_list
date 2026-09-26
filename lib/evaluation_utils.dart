import 'package:flutter/material.dart';

import 'task.dart';
import 'task_completion.dart';
import 'recurrence_utils.dart';

// The two period types the Evaluation screen can show.
enum EvalPeriod { week, month }

// Start and end date (inclusive) of a given period, offset by N periods from today
// (offset 0 = current week/month, -1 = previous, +1 = next).
class PeriodRange {
  final DateTime start;
  final DateTime end;
  const PeriodRange(this.start, this.end);
}

PeriodRange getPeriodRange(EvalPeriod period, int offset) {
  final now = DateTime.now();
  if (period == EvalPeriod.week) {
    // Week starts Monday.
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final start = currentWeekStart.add(Duration(days: 7 * offset));
    final end = start.add(const Duration(days: 6));
    return PeriodRange(start, end);
  } else {
    final targetMonth = DateTime(now.year, now.month + offset, 1);
    final start = DateTime(targetMonth.year, targetMonth.month, 1);
    final end = DateTime(targetMonth.year, targetMonth.month + 1, 0);
    return PeriodRange(start, end);
  }
}

// Every calendar date from start to end, inclusive.
List<DateTime> _datesInRange(PeriodRange range) {
  final dates = <DateTime>[];
  var current = range.start;
  while (!current.isAfter(range.end)) {
    dates.add(current);
    current = current.add(const Duration(days: 1));
  }
  return dates;
}

// Computed stats for one recurring task, over one period.
class TaskEvalStats {
  final Task task;
  final int applicableDays;
  final int doneDays;
  final int
  metTargetDays; // on-time (non-duration) or met-duration (duration-dependent)

  const TaskEvalStats({
    required this.task,
    required this.applicableDays,
    required this.doneDays,
    required this.metTargetDays,
  });

  double get completionRate =>
      applicableDays == 0 ? 0 : doneDays / applicableDays;
  double get targetRate =>
      applicableDays == 0 ? 0 : metTargetDays / applicableDays;
}

// Calculates stats for one recurring task over the given period, using its
// already-loaded list of completion records.
TaskEvalStats evaluateTask(
  Task task,
  List<TaskCompletion> allCompletions,
  PeriodRange range,
) {
  final applicableDates = _datesInRange(range)
      .where((d) => isTaskRelevantForDate(task, d))
      .toList();

  final completionsByDate = <DateTime, TaskCompletion>{};
  for (final c in allCompletions) {
    final dateOnly = DateTime(c.date.year, c.date.month, c.date.day);
    completionsByDate[dateOnly] = c;
  }

  int doneDays = 0;
  int metTargetDays = 0;

  for (final date in applicableDates) {
    final completion = completionsByDate[date];
    if (completion == null || !completion.isDone) continue;
    doneDays++;

    if (task.isDurationDependent) {
      if (completion.actualStart != null && completion.actualEnd != null) {
        final plannedMinutes =
            (task.plannedEnd.hour * 60 + task.plannedEnd.minute) -
            (task.plannedStart.hour * 60 + task.plannedStart.minute);
        final actualMinutes = completion.actualEnd!
            .difference(completion.actualStart!)
            .inMinutes;
        if (actualMinutes >= plannedMinutes) metTargetDays++;
      }
    } else {
      if (completion.actualEnd != null) {
        final deadlineMinutes =
            task.plannedEnd.hour * 60 + task.plannedEnd.minute;
        final actualTimeOfDay = TimeOfDay.fromDateTime(completion.actualEnd!);
        final actualMinutes =
            actualTimeOfDay.hour * 60 + actualTimeOfDay.minute;
        if (actualMinutes <= deadlineMinutes) metTargetDays++;
      }
    }
  }

  return TaskEvalStats(
    task: task,
    applicableDays: applicableDates.length,
    doneDays: doneDays,
    metTargetDays: metTargetDays,
  );
}
