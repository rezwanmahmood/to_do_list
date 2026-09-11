import 'package:flutter/material.dart';

import 'task.dart';
import 'db_helper.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

// Human-readable labels for each recurrence type, in display order.
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
  final TextEditingController _titleController = TextEditingController();
  DateTime _plannedDate = DateTime.now();
  TimeOfDay _plannedStart = TimeOfDay.now();
  TimeOfDay _plannedEnd = TimeOfDay.now();
  RecurrenceType _recurrenceType = RecurrenceType.none;
  bool _isLimitedPeriod = false;
  DateTime? _recurrenceEndDate;
  bool _isDurationDependent = false;

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
    if (picked != null) setState(() => _plannedStart = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _plannedEnd,
    );
    if (picked != null) setState(() => _plannedEnd = picked);
  }

  Future<void> _saveTask() async {
    if (_titleController.text.isEmpty) return;

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

    final newTask = Task(
      title: _titleController.text,
      recurrenceType: _recurrenceType,
      isDurationDependent:
          _recurrenceType != RecurrenceType.none && _isDurationDependent,
      date: _plannedDate,
      recurrenceEndDate:
          _recurrenceType != RecurrenceType.none && _isLimitedPeriod
          ? _recurrenceEndDate
          : null,
      plannedStart: _plannedStart,
      plannedEnd: _plannedEnd,
    );
    final saved = await DBHelper.insertTask(newTask);
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Task')),
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
                  child: Text('Start: ${_plannedStart.format(context)}'),
                ),
                TextButton(
                  onPressed: _pickEndTime,
                  child: Text('End: ${_plannedEnd.format(context)}'),
                ),
              ],
            ),
            DropdownButtonFormField<RecurrenceType>(
              initialValue: _recurrenceType,
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: recurrenceLabels.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (val) => setState(() {
                _recurrenceType = val ?? RecurrenceType.none;
                if (_recurrenceType == RecurrenceType.none) {
                  _isLimitedPeriod = false;
                  _recurrenceEndDate = null;
                }
              }),
            ),
            if (_recurrenceType != RecurrenceType.none)
              Row(
                children: [
                  const Text('Duration dependent?'),
                  Switch(
                    value: _isDurationDependent,
                    onChanged: (val) =>
                        setState(() => _isDurationDependent = val),
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
              onPressed: _saveTask,
              child: const Text('Save Task'),
            ),
          ],
        ),
      ),
    );
  }
}
