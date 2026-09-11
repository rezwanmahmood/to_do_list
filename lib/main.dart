import 'package:flutter/material.dart';

import 'task.dart';
import 'task_completion.dart';
import 'db_helper.dart';
import 'day_detail_screen.dart';
import 'add_task_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: TaskListScreen());
  }
}

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  List<Task> tasks = [];
  Map<int, TaskCompletion> _todayCompletions = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  // Pulls every saved task from the database into memory, on app start.
  Future<void> _loadTasks() async {
    final loaded = await DBHelper.getAllTasks();
    final completions = await DBHelper.getCompletionsForDate(DateTime.now());
    setState(() {
      tasks = loaded;
      _todayCompletions = {for (var c in completions) c.taskId: c};
    });
  }

  // Is this task ticked, specifically for today?
  bool _isDoneToday(Task task) => _todayCompletions[task.id]?.isDone ?? false;

  // What time was it completed today, if at all?
  DateTime? _actualEndToday(Task task) => _todayCompletions[task.id]?.actualEnd;

  // What time was this task actually started today, if at all?
  DateTime? _actualStartToday(Task task) =>
      _todayCompletions[task.id]?.actualStart;

  // Records the moment a duration-dependent task was actually started.
  Future<void> _startTask(Task task) async {
    final completion = TaskCompletion(
      taskId: task.id!,
      date: DateTime.now(),
      isDone: false,
      actualStart: DateTime.now(),
    );
    await DBHelper.saveCompletion(completion);
    setState(() {
      _todayCompletions[task.id!] = completion;
    });
  }

  // Records the moment a duration-dependent task was actually finished, keeping its start time.
  Future<void> _finishTask(Task task) async {
    final existingStart = _actualStartToday(task);
    final completion = TaskCompletion(
      taskId: task.id!,
      date: DateTime.now(),
      isDone: true,
      actualStart: existingStart,
      actualEnd: DateTime.now(),
    );
    await DBHelper.saveCompletion(completion);
    setState(() {
      _todayCompletions[task.id!] = completion;
    });
  }

  // Returns true if this task applies to the given date (works for any day, not just today).
  bool isTaskRelevantForDate(Task task, DateTime targetDate) {
    final targetOnly = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final taskDateOnly = DateTime(
      task.date.year,
      task.date.month,
      task.date.day,
    );

    // One-time tasks: only match their exact date.
    if (task.recurrenceType == RecurrenceType.none) {
      return taskDateOnly.isAtSameMomentAs(targetOnly);
    }

    // Recurring tasks must have started on/before the target date.
    if (taskDateOnly.isAfter(targetOnly)) return false;

    // If it has a limited period, target must not be past that end date.
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

  // Checks if targetDate falls on the same day-of-month as startDate, at a multiple of
  // 'intervalMonths' months since the start (e.g. every 2 months, every 3 months).
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

  // Returns true if this task should appear in today's list.
  bool _isRelevantToday(Task task) =>
      isTaskRelevantForDate(task, DateTime.now());

  Future<void> _confirmCompletion(Task task) async {
    DateTime chosenTime = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Confirm completion time'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(TimeOfDay.fromDateTime(chosenTime).format(context)),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(chosenTime),
                      );
                      if (picked != null) {
                        final now = DateTime.now();
                        setDialogState(() {
                          chosenTime = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                      }
                    },
                    child: const Text('Change time'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      final completion = TaskCompletion(
        taskId: task.id!,
        date: DateTime.now(),
        isDone: true,
        actualEnd: chosenTime,
      );
      await DBHelper.saveCompletion(completion);
      setState(() {
        _todayCompletions[task.id!] = completion;
      });
    }
  }

  Future<void> _uncheckTask(Task task) async {
    final completion = TaskCompletion(
      taskId: task.id!,
      date: DateTime.now(),
      isDone: false,
      actualEnd: null,
    );
    await DBHelper.saveCompletion(completion);
    setState(() {
      _todayCompletions[task.id!] = completion;
    });
  }

  // Opens a calendar picker (past or future), then navigates to that day's read-only detail view.
  Future<void> _openDayDetail() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DayDetailScreen(date: picked)),
      );
    }
  }

  Future<void> _openAddTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTaskScreen()),
    );
    if (result != null) {
      setState(() {
        tasks.add(result as Task);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _openDayDetail,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: tasks.where(_isRelevantToday).length,
        itemBuilder: (context, index) {
          final task = tasks.where(_isRelevantToday).toList()[index];
          final doneToday = _isDoneToday(task);
          final actualStartToday = _actualStartToday(task);
          final actualEndToday = _actualEndToday(task);

          if (task.isDurationDependent) {
            // Duration-dependent: Start -> Finish flow instead of a plain tick.
            String statusText;
            if (doneToday &&
                actualStartToday != null &&
                actualEndToday != null) {
              final plannedMinutes =
                  (task.plannedEnd.hour * 60 + task.plannedEnd.minute) -
                  (task.plannedStart.hour * 60 + task.plannedStart.minute);
              final actualMinutes = actualEndToday
                  .difference(actualStartToday)
                  .inMinutes;
              final metDuration = actualMinutes >= plannedMinutes;
              statusText =
                  '✓ ${TimeOfDay.fromDateTime(actualStartToday).format(context)} - '
                  '${TimeOfDay.fromDateTime(actualEndToday).format(context)}'
                  '  (${actualMinutes}min, planned ${plannedMinutes}min)'
                  '${metDuration ? '' : '  ⚠ short'}';
            } else if (actualStartToday != null) {
              statusText =
                  'Started at ${TimeOfDay.fromDateTime(actualStartToday).format(context)}';
            } else {
              statusText =
                  '${task.plannedStart.format(context)} - ${task.plannedEnd.format(context)}';
            }

            return ListTile(
              title: Text(task.title),
              subtitle: Text(statusText),
              trailing: doneToday
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : ElevatedButton(
                      onPressed: actualStartToday == null
                          ? () => _startTask(task)
                          : () => _finishTask(task),
                      child: Text(
                        actualStartToday == null ? 'Start' : 'Finish',
                      ),
                    ),
            );
          }

          // Normal tasks: simple tick, unchanged behavior.
          return CheckboxListTile(
            title: Text(task.title),
            subtitle: Text(
              '${task.plannedStart.format(context)} - ${task.plannedEnd.format(context)}'
              '${task.isRecurring ? '  (Daily)' : ''}'
              '${actualEndToday != null ? '  ✓ ${TimeOfDay.fromDateTime(actualEndToday).format(context)}' : ''}',
            ),
            value: doneToday,
            onChanged: (value) {
              if (value == true && !doneToday) {
                _confirmCompletion(task);
              } else if (value == false) {
                _uncheckTask(task);
              }
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTask,
        child: const Icon(Icons.add),
      ),
    );
  }
}
