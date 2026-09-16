import 'package:flutter/material.dart';

// The different repeat patterns a task can have. 'none' means one-time.
enum RecurrenceType {
  none,
  daily,
  weekly,
  fortnightly,
  monthly,
  biMonthly,
  triMonthly,
  halfYearly,
  annually,
}

class Task {
  int? id;
  String title;
  RecurrenceType recurrenceType;
  DateTime date;
  DateTime? recurrenceEndDate;
  bool isDurationDependent;
  int? parentTaskId; // null = top-level task, otherwise the id of its parent
  TimeOfDay plannedStart;
  TimeOfDay plannedEnd;
  DateTime? actualStart;
  DateTime? actualEnd;
  bool isDone;

  Task({
    this.id,
    required this.title,
    required this.recurrenceType,
    required this.date,
    this.recurrenceEndDate,
    this.isDurationDependent = false,
    this.parentTaskId,
    required this.plannedStart,
    required this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.isDone = false,
  });

  bool get isRecurring => recurrenceType != RecurrenceType.none;

  // Converts this Task into a plain Map, the format sqflite needs to save it.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'recurrenceType': recurrenceType.index,
      'isDurationDependent': isDurationDependent ? 1 : 0,
      'parentTaskId': parentTaskId,
      'date': date.toIso8601String(),
      'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
      'plannedStartHour': plannedStart.hour,
      'plannedStartMinute': plannedStart.minute,
      'plannedEndHour': plannedEnd.hour,
      'plannedEndMinute': plannedEnd.minute,
      'actualEnd': actualEnd?.toIso8601String(),
      'isDone': isDone ? 1 : 0,
    };
  }

  // Rebuilds a Task object from a database row (the reverse of toMap).
  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      recurrenceType: RecurrenceType.values[map['recurrenceType']],
      isDurationDependent: map['isDurationDependent'] == 1,
      parentTaskId: map['parentTaskId'],
      date: DateTime.parse(map['date']),
      recurrenceEndDate: map['recurrenceEndDate'] != null
          ? DateTime.parse(map['recurrenceEndDate'])
          : null,
      plannedStart: TimeOfDay(
        hour: map['plannedStartHour'],
        minute: map['plannedStartMinute'],
      ),
      plannedEnd: TimeOfDay(
        hour: map['plannedEndHour'],
        minute: map['plannedEndMinute'],
      ),
      actualEnd: map['actualEnd'] != null
          ? DateTime.parse(map['actualEnd'])
          : null,
      isDone: map['isDone'] == 1,
    );
  }
}
