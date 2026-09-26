import 'package:flutter/material.dart';

import 'task.dart';
import 'db_helper.dart';

class AddTaskScreen extends StatefulWidget {
  final int? parentTaskId;
  final Task? editingTask;

  const AddTaskScreen({super.key, this.parentTaskId, this.editingTask});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

const Map<RecurrenceType, String> recurrenceLabels = {
  RecurrenceType.none: 'One-time',
  RecurrenceType.daily: 'Daily',
  RecurrenceType.weekly: 'Weekly',
  RecurrenceType.fortnightly: 'Fortnightly',
  RecurrenceType.monthly: 'Monthly',
  RecurrenceType.biMonthly: 'Bi-monthly',
  RecurrenceType.triMonthly: 'Tri-monthly',
  RecurrenceType.halfYearly: 'Half-yearly',
  RecurrenceType.annually: 'Annually',
};

class _AddTaskScreenState extends State<AddTaskScreen> {
  late final TextEditingController _titleController;
  late DateTime _plannedDate;
  late TimeOfDay _plannedStart;
  late TimeOfDay _plannedEnd;
  late RecurrenceType _recurrenceType;
  late bool _isLimitedPeriod;
  DateTime? _recurrenceEndDate;
  late bool _isDurationDependent;
  bool _isReady = true;
  Task? _parentTask;

  int? get _effectiveParentId =>
      widget.editingTask?.parentTaskId ?? widget.parentTaskId;

  @override
  void initState() {
    super.initState();
    final editing = widget.editingTask;
    _titleController = TextEditingController(text: editing?.title ?? '');
    _plannedDate = editing?.date ?? DateTime.now();
    _plannedStart = editing?.plannedStart ?? TimeOfDay.now();
    _plannedEnd = editing?.plannedEnd ?? TimeOfDay.now();
    _recurrenceType = editing?.recurrenceType ?? RecurrenceType.none;
    _recurrenceEndDate = editing?.recurrenceEndDate;
    _isLimitedPeriod = editing?.recurrenceEndDate != null;
    _isDurationDependent = editing?.isDurationDependent ?? false;

    if (_effectiveParentId != null) {
      _isReady = false;
      _loadParentTask();
    }
  }

  Future<void> _loadParentTask() async {
    final parent = await DBHelper.getTaskById(_effectiveParentId!);
    setState(() {
      _parentTask = parent;
      if (widget.editingTask == null) {
        _recurrenceType = parent?.recurrenceType ?? RecurrenceType.none;
      }
      _isReady = true;
    });
  }

  Future<void> _pickPlannedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _plannedDate = picked);
  }

  Future<void> _pickRecurrenceEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recurrenceEndDate ?? _plannedDate,
      firstDate: _plannedDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _recurrenceEndDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _plannedStart,
    );
    if (picked != null) {
      setState(() {
        _plannedStart = picked;
        if (!_isDurationDependent) _plannedEnd = picked;
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _plannedEnd,
    );
    if (picked != null) setState(() => _plannedEnd = picked);
  }

  Future<void> _saveTask() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task name cannot be empty')),
      );
      return;
    }

    final startMinutes = _plannedStart.hour * 60 + _plannedStart.minute;
    final endMinutes = _plannedEnd.hour * 60 + _plannedEnd.minute;
    if (endMinutes < startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be at or after start time'),
        ),
      );
      return;
    }
    if (_isDurationDependent && endMinutes == startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Duration-dependent tasks need an end time later than start time',
          ),
        ),
      );
      return;
    }

    if (_parentTask != null && _isDurationDependent) {
      final parentDuration =
          (_parentTask!.plannedEnd.hour * 60 + _parentTask!.plannedEnd.minute) -
          (_parentTask!.plannedStart.hour * 60 +
              _parentTask!.plannedStart.minute);
      final subDuration = endMinutes - startMinutes;
      if (subDuration > parentDuration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Sub-task duration cannot exceed the parent task's ($parentDuration min)",
            ),
          ),
        );
        return;
      }
    }

    if (_parentTask != null &&
        _isLimitedPeriod &&
        _recurrenceEndDate != null &&
        _parentTask!.recurrenceEndDate != null &&
        _recurrenceEndDate!.isAfter(_parentTask!.recurrenceEndDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Sub-task's end date cannot be later than the parent task's",
          ),
        ),
      );
      return;
    }

    final task = Task(
      id: widget.editingTask?.id,
      title: _titleController.text,
      recurrenceType: _recurrenceType,
      isDurationDependent: _isDurationDependent,
      parentTaskId: _effectiveParentId,
      date: _plannedDate,
      recurrenceEndDate:
          _recurrenceType != RecurrenceType.none && _isLimitedPeriod
          ? _recurrenceEndDate
          : null,
      plannedStart: _plannedStart,
      plannedEnd: _plannedEnd,
    );

    if (widget.editingTask != null) {
      await DBHelper.updateTaskFull(task);
    } else {
      await DBHelper.insertTask(task);
    }
    if (mounted) Navigator.pop(context, task);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editingTask != null;
    final isSubTask = _effectiveParentId != null;
    final titleText = isEditing
        ? (isSubTask ? 'Edit Sub-task' : 'Edit Task')
        : (isSubTask ? 'Add Sub-task' : 'Add Task');

    return Scaffold(
      appBar: AppBar(title: Text(titleText)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(hintText: 'Task name'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _pickPlannedDate,
                  child: Text(
                    '${_plannedDate.year}-${_plannedDate.month.toString().padLeft(2, '0')}-${_plannedDate.day.toString().padLeft(2, '0')}',
                  ),
                ),
                TextButton(
                  onPressed: _pickStartTime,
                  child: Text(
                    _isDurationDependent
                        ? 'Start: ${_plannedStart.format(context)}'
                        : 'Time: ${_plannedStart.format(context)}',
                  ),
                ),
                if (_isDurationDependent)
                  TextButton(
                    onPressed: _pickEndTime,
                    child: Text('End: ${_plannedEnd.format(context)}'),
                  ),
              ],
            ),
            if (!isSubTask)
              DropdownButtonFormField<RecurrenceType>(
                initialValue: _recurrenceType,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: recurrenceLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (val) => setState(() {
                  _recurrenceType = val ?? RecurrenceType.none;
                  if (_recurrenceType == RecurrenceType.none) {
                    _isLimitedPeriod = false;
                    _recurrenceEndDate = null;
                  }
                }),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _isReady
                      ? 'Repeats: ${recurrenceLabels[_recurrenceType]} (matches parent task)'
                      : 'Loading parent task...',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            Row(
              children: [
                const Text('Duration dependent?'),
                Switch(
                  value: _isDurationDependent,
                  onChanged: (val) => setState(() {
                    _isDurationDependent = val;
                    if (!val) _plannedEnd = _plannedStart;
                  }),
                ),
              ],
            ),
            if (_recurrenceType != RecurrenceType.none)
              Row(
                children: [
                  const Text('Limited period?'),
                  Checkbox(
                    value: _isLimitedPeriod,
                    onChanged: (val) =>
                        setState(() => _isLimitedPeriod = val ?? false),
                  ),
                  if (_isLimitedPeriod)
                    TextButton(
                      onPressed: _pickRecurrenceEndDate,
                      child: Text(
                        _recurrenceEndDate == null
                            ? 'Pick end date'
                            : 'Until: ${_recurrenceEndDate!.year}-${_recurrenceEndDate!.month.toString().padLeft(2, '0')}-${_recurrenceEndDate!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isReady ? _saveTask : null,
              child: Text(isEditing ? 'Save Changes' : 'Save Task'),
            ),
          ],
        ),
      ),
    );
  }
}
