import 'package:flutter/material.dart';

import 'task.dart';
import 'db_helper.dart';
import 'evaluation_utils.dart';

class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({super.key});

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _weekOffset = 0;
  int _monthOffset = 0;
  List<Task> _allTasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final tasks = await DBHelper.getAllTasks();
    setState(() {
      _allTasks = tasks.where((t) => t.parentTaskId == null).toList();
      _loading = false;
    });
  }

  String _formatRange(PeriodRange range) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(range.start)}  to  ${fmt(range.end)}';
  }

  Widget _buildStatsTab(
    EvalPeriod period,
    int offset,
    void Function(int) onOffsetChange,
  ) {
    final range = getPeriodRange(period, offset);
    final recurringTasks = _allTasks
        .where((t) => t.recurrenceType != RecurrenceType.none)
        .toList();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => onOffsetChange(offset - 1),
            ),
            Text(_formatRange(range)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => onOffsetChange(offset + 1),
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<List<TaskEvalStats>>(
            future: _computeStats(recurringTasks, range),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final stats = snapshot.data!;
              if (stats.isEmpty) {
                return const Center(child: Text('No recurring tasks yet'));
              }
              return ListView.builder(
                itemCount: stats.length,
                itemBuilder: (context, index) {
                  final s = stats[index];
                  final targetLabel = s.task.isDurationDependent
                      ? 'met duration'
                      : 'on time';
                  return ListTile(
                    title: Text(s.task.title),
                    subtitle: Text(
                      'Done: ${s.doneDays}/${s.applicableDays} days  (${(s.completionRate * 100).round()}%)\n'
                      '${targetLabel[0].toUpperCase()}${targetLabel.substring(1)}: ${s.metTargetDays}/${s.applicableDays} days  (${(s.targetRate * 100).round()}%)',
                    ),
                    isThreeLine: true,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<List<TaskEvalStats>> _computeStats(
    List<Task> tasks,
    PeriodRange range,
  ) async {
    final results = <TaskEvalStats>[];
    for (final task in tasks) {
      final completions = await DBHelper.getCompletionsForTask(task.id!);
      results.add(evaluateTask(task, completions, range));
    }
    return results;
  }

  Widget _buildOneTimeTab() {
    // One-time tab shares the week/month offset from whichever period tab was last active.
    final period = _tabController.index == 1
        ? EvalPeriod.month
        : EvalPeriod.week;
    final offset = _tabController.index == 1 ? _monthOffset : _weekOffset;
    final range = getPeriodRange(period, offset);
    final oneTimeTasks = _allTasks
        .where((t) => t.recurrenceType == RecurrenceType.none)
        .where((t) {
          final d = DateTime(t.date.year, t.date.month, t.date.day);
          return !d.isBefore(range.start) && !d.isAfter(range.end);
        })
        .toList();

    if (oneTimeTasks.isEmpty) {
      return const Center(child: Text('No one-time tasks in this period'));
    }
    return ListView.builder(
      itemCount: oneTimeTasks.length,
      itemBuilder: (context, index) {
        final t = oneTimeTasks[index];
        return ListTile(
          title: Text(t.title),
          subtitle: Text(
            '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluation'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Week'),
            Tab(text: 'Month'),
            Tab(text: 'One-time'),
          ],
          onTap: (_) => setState(() {}),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStatsTab(
                  EvalPeriod.week,
                  _weekOffset,
                  (v) => setState(() => _weekOffset = v),
                ),
                _buildStatsTab(
                  EvalPeriod.month,
                  _monthOffset,
                  (v) => setState(() => _monthOffset = v),
                ),
                _buildOneTimeTab(),
              ],
            ),
    );
  }
}
