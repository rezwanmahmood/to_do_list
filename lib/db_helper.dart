import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'task.dart';
import 'task_completion.dart';

class DBHelper {
  static Database? _db;

  // Returns the open database, creating/opening it the first time this is called.
  static Future<Database> getDatabase() async {
    if (_db != null) return _db!;

    final path = join(await getDatabasesPath(), 'tasks.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
         CREATE TABLE tasks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            recurrenceType INTEGER,
            isDurationDependent INTEGER,
            parentTaskId INTEGER,
            date TEXT,
            recurrenceEndDate TEXT,
            plannedStartHour INTEGER,
            plannedStartMinute INTEGER,
            plannedEndHour INTEGER,
            plannedEndMinute INTEGER,
            actualEnd TEXT,
            isDone INTEGER
          )
        ''');
        await db.execute('''
                    CREATE TABLE completions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            taskId INTEGER,
            date TEXT,
            isDone INTEGER,
            isRejected INTEGER,
            actualStart TEXT,
            actualEnd TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  // Saves a new task, returns it with the id the database assigned.
  static Future<Task> insertTask(Task task) async {
    final db = await getDatabase();
    final id = await db.insert('tasks', task.toMap());
    task.id = id;
    return task;
  }

  // Loads every saved task.
  static Future<List<Task>> getAllTasks() async {
    final db = await getDatabase();
    final maps = await db.query('tasks');
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  // Loads a single task by its id.
  static Future<Task?> getTaskById(int id) async {
    final db = await getDatabase();
    final maps = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Task.fromMap(maps.first);
  }

  // Updates an existing task (used when ticking/unticking, editing, etc).
  static Future<void> updateTask(Task task) async {
    final db = await getDatabase();
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // Removes a task permanently.
  static Future<void> deleteTask(int id) async {
    final db = await getDatabase();
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // Gets the direct children (sub-tasks) of a given task.
  static Future<List<Task>> getSubTasks(int parentTaskId) async {
    final db = await getDatabase();
    final maps = await db.query(
      'tasks',
      where: 'parentTaskId = ?',
      whereArgs: [parentTaskId],
    );
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  // Gets only top-level tasks (no parent) — what the home screen should show.
  static Future<List<Task>> getTopLevelTasks() async {
    final db = await getDatabase();
    final maps = await db.query('tasks', where: 'parentTaskId IS NULL');
    return maps.map((m) => Task.fromMap(m)).toList();
  }

  // Saves or updates a completion record for a specific task and day.
  static Future<void> saveCompletion(TaskCompletion completion) async {
    final db = await getDatabase();
    final map = completion.toMap();
    final existing = await db.query(
      'completions',
      where: 'taskId = ? AND date = ?',
      whereArgs: [map['taskId'], map['date']],
    );
    if (existing.isNotEmpty) {
      await db.update(
        'completions',
        map,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('completions', map);
    }
  }

  // Gets all completion records for a specific task (used for weekly/monthly evaluation).
  static Future<List<TaskCompletion>> getCompletionsForTask(int taskId) async {
    final db = await getDatabase();
    final maps = await db.query(
      'completions',
      where: 'taskId = ?',
      whereArgs: [taskId],
    );
    return maps.map((m) => TaskCompletion.fromMap(m)).toList();
  }

  // Gets every completion record for one specific date (used to check today's status for recurring tasks).
  static Future<List<TaskCompletion>> getCompletionsForDate(
    DateTime date,
  ) async {
    final db = await getDatabase();
    final dateOnly = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String();
    final maps = await db.query(
      'completions',
      where: 'date = ?',
      whereArgs: [dateOnly],
    );
    return maps.map((m) => TaskCompletion.fromMap(m)).toList();
  }
}
