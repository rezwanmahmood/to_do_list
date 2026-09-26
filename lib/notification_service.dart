import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import 'task.dart';
import 'recurrence_utils.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Set by main.dart at startup. Called whenever a notification is tapped
  // while the app is already running.
  static void Function(String payload)? onNotificationPayload;

  // Holds a payload if the app was launched (cold start) by tapping a
  // notification — checked once, right after the app's first frame.
  static String? pendingLaunchPayload;

  // Call once, when the app starts. Sets up timezones and the notification system.
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    // Assumes Bangladesh time. If this app is ever used while traveling
    // to a different timezone, this line would need to change.
    tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        // ignore: avoid_print
        print(
          '>>> ACTION TAPPED: actionId=${response.actionId} payload=${response.payload}',
        );
        if (response.payload != null) {
          onNotificationPayload?.call(response.payload!);
        }
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      pendingLaunchPayload = launchDetails?.notificationResponse?.payload;
    }

    // Explicitly create the notification channels before scheduling into them —
    // Android 13+ can silently drop scheduled notifications into channels
    // that were never formally registered, even though show() still works.
    const testChannel = AndroidNotificationChannel(
      'test_channel',
      'Test Notifications',
      description: 'Used to verify notifications are working',
      importance: Importance.max,
    );
    const taskChannel = AndroidNotificationChannel(
      'task_alarms',
      'Task Alarms',
      description: 'Alarms for your planned tasks',
      importance: Importance.max,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(testChannel);
    await androidPlugin?.createNotificationChannel(taskChannel);

    await _requestPermissions();
  }

  static Future<void> _requestPermissions() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notifGranted = await androidPlugin?.requestNotificationsPermission();
    final alarmGranted = await androidPlugin?.requestExactAlarmsPermission();
    // ignore: avoid_print
    print(
      '>>> PERMISSIONS: notifications=$notifGranted, exactAlarms=$alarmGranted',
    );
  }

  // Finds the next date (today or later, up to a year out) that this task
  // actually applies to, based on its recurrence pattern.
  static DateTime? _nextOccurrence(Task task) {
    final today = DateTime.now();
    for (int i = 0; i < 366; i++) {
      final candidate = DateTime(
        today.year,
        today.month,
        today.day,
      ).add(Duration(days: i));
      if (isTaskRelevantForDate(task, candidate)) return candidate;
    }
    return null;
  }

  // Combines a date with a TimeOfDay into one DateTime, in the local timezone.
  static tz.TZDateTime _combine(DateTime date, TimeOfDay time) {
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  // Cancels any alarms previously scheduled for this task (both Start and End slots).
  static Future<void> cancelTaskAlarms(int taskId) async {
    await _plugin.cancel(id: taskId * 10 + 1); // Start / deadline alarm
    await _plugin.cancel(id: taskId * 10 + 2); // End alarm
  }

  // Schedules the actual alarm(s) for one leaf task, based on its next occurrence.
  // Non-duration tasks get one alarm (their single deadline time) with Accept/Reject.
  // Duration-dependent tasks get that same Start alarm, plus a second End alarm.
  static Future<void> scheduleTaskAlarms(Task task) async {
    await cancelTaskAlarms(task.id!);

    final nextDate = _nextOccurrence(task);
    if (nextDate == null) return;

    final startTime = _combine(nextDate, task.plannedStart);
    // Don't schedule alarms for a moment that's already passed today.
    if (startTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    const androidDetails = AndroidNotificationDetails(
      'task_alarms',
      'Task Alarms',
      channelDescription: 'Alarms for your planned tasks',
      importance: Importance.max,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('accept', 'Accept'),
        AndroidNotificationAction('reject', 'Reject'),
      ],
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id: task.id! * 10 + 1,
      title: task.title,
      body: task.isDurationDependent
          ? 'Time to start this task'
          : 'Deadline for this task',
      scheduledDate: startTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: 'start:${task.id}',
    );

    if (task.isDurationDependent) {
      final endTime = _combine(nextDate, task.plannedEnd);
      const endDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'task_alarms',
          'Task Alarms',
          channelDescription: 'Alarms for your planned tasks',
          importance: Importance.max,
          priority: Priority.high,
        ),
      );
      await _plugin.zonedSchedule(
        id: task.id! * 10 + 2,
        title: task.title,
        body: 'Confirm when you actually finished this task',
        scheduledDate: endTime,
        notificationDetails: endDetails,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        payload: 'end:${task.id}',
      );
    }
  }

  // Reschedules alarms for every leaf task (called once when the home screen loads).
  static Future<void> rescheduleAllLeafTasks(
    List<Task> allTasks,
    List<int> parentIds,
  ) async {
    final leafTasks = allTasks.where((t) => !parentIds.contains(t.id)).toList();
    for (final task in leafTasks) {
      await scheduleTaskAlarms(task);
    }
  }

  // Fires an immediate notification (no scheduling/delay) — used to isolate
  // whether the problem is with display itself or with scheduled/delayed alarms.
  static Future<void> showImmediateTestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Used to verify notifications are working',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    try {
      await _plugin.show(
        id: 1,
        title: 'Immediate Test',
        body: 'This should appear right now',
        notificationDetails: details,
      );
      // ignore: avoid_print
      print('>>> IMMEDIATE notification shown');
    } catch (e) {
      // ignore: avoid_print
      print('>>> IMMEDIATE FAILED: $e');
    }
  }

  // Fires a test notification 10 seconds from now — used only to confirm
  // the whole pipeline (permissions + display) actually works.
  static Future<void> scheduleTestNotification() async {
    final scheduledTime = tz.TZDateTime.now(tz.local)
        .add(const Duration(seconds: 10));

    const androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Used to verify notifications are working',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    // ignore: avoid_print
    print(
      '>>> SCHEDULING test notification for $scheduledTime (now is ${tz.TZDateTime.now(tz.local)})',
    );
    try {
      await _plugin.zonedSchedule(
        id: 0,
        title: 'Test Notification',
        body: 'If you see this, notifications are working!',
        scheduledDate: scheduledTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
      // ignore: avoid_print
      print('>>> SCHEDULED successfully');
    } catch (e) {
      // ignore: avoid_print
      print('>>> SCHEDULING FAILED: $e');
    }
  }
}
