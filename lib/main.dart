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
  final Set<int> _expandedTaskIds = {};
  final Map<int, List<Task>> _subTasksByParent = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  // Pulls every saved top-level task from the database into memory, on app start.
  Future<void> _loadTasks() async {
    final loaded = await DBHelper.getTopLevelTasks();
    final completions = await DBHelper.getCompletionsForDate(DateTime.now());
    setState(() {
      tasks = loaded;
      _todayCompletions = {for (var c in completions) c.taskId: c};
    });
  }

  // Expands a task to show its sub-tasks (loading them the first time), or collapses it.
  Future<void> _toggleExpand(Task task) async {
    if (_expandedTaskIds.contains(task.id)) {
      setState(() => _expandedTaskIds.remove(task.id));
      return;
    }
    final subTasks = await DBHelper.getSubTasks(task.id!);
    setState(() {
      _subTasksByParent[task.id!] = subTasks;
      _expandedTaskIds.add(task.id!);
    });
  }

  // Opens Add Task screen pre-linked to a parent, for creating a sub-task.
  Future<void> _openAddSubTask(Task parent) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskScreen(parentTaskId: parent.id),
      ),
    );
    if (result != null) {
      setState(() {
        final list = _subTasksByParent[parent.id!] ?? [];
        list.add(result as Task);
        _subTasksByParent[parent.id!] = list;
        _expandedTaskIds.add(parent.id!);
      });
    }
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
    await _updateParentStatus(task.parentTaskId);
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
      await _updateParentStatus(task.parentTaskId);
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
    await _updateParentStatus(task.parentTaskId);
  }

  // After a sub-task's status changes, checks if all of its siblings are done today,
  // and if so, auto-completes the parent too. If not, un-completes the parent (in case
  // it was previously auto-completed and a sibling was just unticked).
  Future<void> _updateParentStatus(int? parentTaskId) async {
    if (parentTaskId == null) return;
    final siblings = await DBHelper.getSubTasks(parentTaskId);
    if (siblings.isEmpty) return;

    final allDone = siblings.every(
      (s) => _todayCompletions[s.id]?.isDone ?? false,
    );
    final parentCompletion = TaskCompletion(
      taskId: parentTaskId,
      date: DateTime.now(),
      isDone: allDone,
      actualEnd: allDone ? DateTime.now() : null,
    );
    await DBHelper.saveCompletion(parentCompletion);
    setState(() {
      _todayCompletions[parentTaskId] = parentCompletion;
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

  // Builds one task row (used for both top-level tasks and sub-tasks), with indentation
  // increasing per depth level so nested sub-tasks visually appear as a tree.
  Widget _buildTaskTile(Task task, int depth) {
    final doneToday = _isDoneToday(task);
    final actualStartToday = _actualStartToday(task);
    final actualEndToday = _actualEndToday(task);
    final isExpanded = _expandedTaskIds.contains(task.id);
    final subTasks = _subTasksByParent[task.id] ?? [];

    Widget tile;

    if (task.isDurationDependent) {
      String statusText;
      if (doneToday && actualStartToday != null && actualEndToday != null) {
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

      tile = ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 24, right: 16),
        leading: IconButton(
          icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right),
          onPressed: () => _toggleExpand(task),
        ),
        title: Text(task.title),
        subtitle: Text(statusText),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'Add sub-task',
              onPressed: () => _openAddSubTask(task),
            ),
            doneToday
                ? const Icon(Icons.check_circle, color: Colors.green)
                : ElevatedButton(
                    onPressed: actualStartToday == null
                        ? () => _startTask(task)
                        : () => _finishTask(task),
                    child: Text(actualStartToday == null ? 'Start' : 'Finish'),
                  ),
          ],
        ),
      );
    } else {
      tile = CheckboxListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 24, right: 16),
        secondary: IconButton(
          icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right),
          onPressed: () => _toggleExpand(task),
        ),
        title: Text(task.title),
        subtitle: Text(
          '${task.plannedStart.format(context)} - ${task.plannedEnd.format(context)}'
          '${task.isRecurring ? '  (${recurrenceLabels[task.recurrenceType]})' : ''}'
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
    }

    if (!isExpanded) return tile;

    //     // When expanded, show the tile followed by each sub-task (recursively, so a sub-task
    // can itself be expanded to reveal its own children). Each sub-task is filtered by its
    // own date/recurrence relevance, same as top-level tasks.
    final visibleSubTasks = subTasks.where(_isRelevantToday).toList();
    return Column(
      children: [
        tile,
        ...visibleSubTasks.map((sub) => _buildTaskTile(sub, depth + 1)),
        Padding(
          padding: EdgeInsets.only(left: 16.0 + (depth + 1) * 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openAddSubTask(task),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add sub-task'),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topLevelVisible = tasks.where(_isRelevantToday).toList();
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
        itemCount: topLevelVisible.length,
        itemBuilder: (context, index) =>
            _buildTaskTile(topLevelVisible[index], 0),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTask,
        child: const Icon(Icons.add),
      ),
    );
  }
}
