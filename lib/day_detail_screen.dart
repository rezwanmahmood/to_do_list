import 'package:flutter/material.dart';

import 'task.dart';
import 'task_completion.dart';
import 'db_helper.dart';

class DayDetailScreen extends StatefulWidget {
  final DateTime date;

  const DayDetailScreen({super.key, required this.date});

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  List<Task> _relevantTasks = [];
  Map<int, TaskCompletion> _completions = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Same relevance rule as the main screen, just checked against widget.date instead of today.
  bool _isRelevantForDate(Task task) {
    final targetOnly = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    );
    final taskDateOnly = DateTime(
      task.date.year,
      task.date.month,
      task.date.day,
    );

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

  Future<void> _loadData() async {
    final allTasks = await DBHelper.getAllTasks();
    final completions = await DBHelper.getCompletionsForDate(widget.date);
    setState(() {
      _relevantTasks = allTasks.where(_isRelevantForDate).toList();
      _completions = {for (var c in completions) c.taskId: c};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text(dateLabel)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _relevantTasks.isEmpty
          ? const Center(child: Text('No tasks for this day'))
          : ListView.builder(
              itemCount: _relevantTasks.length,
              itemBuilder: (context, index) {
                final task = _relevantTasks[index];
                final completion = _completions[task.id];
                final isDone = completion?.isDone ?? false;
                final actualEnd = completion?.actualEnd;

                return ListTile(
                  leading: Icon(
                    isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isDone ? Colors.green : Colors.grey,
                  ),
                  title: Text(task.title),
                  subtitle: Text(
                    '${task.plannedStart.format(context)} - ${task.plannedEnd.format(context)}'
                    '${actualEnd != null ? '  •  Done at ${TimeOfDay.fromDateTime(actualEnd).format(context)}' : ''}',
                  ),
                );
              },
            ),
    );
  }
}
