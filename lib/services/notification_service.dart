// lib/services/notification_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/hive_storage.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
    if (_initialized) return;

    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings settings =
          InitializationSettings(android: androidSettings);
      await _notifications.initialize(settings);

      _initialized = true;

      if (Platform.isAndroid) {
        await Permission.notification.request();
        final batteryStatus =
            await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Errore init notifiche: $e',
        backgroundColor: Colors.red.shade700,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  static Future scheduleDailyReminder() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    await init();

    try {
      final String timeStr = AppStorage.getNotificationTime() ?? '20:00';
      final parts = timeStr.split(':');
      final int hh = int.parse(parts[0]);
      final int mm = int.parse(parts[1]);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'daily_reminder_channel',
        'Promemoria ClimaSense',
        channelDescription: 'Ti ricorda di inserire i dati PdC',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );
      const NotificationDetails details =
          NotificationDetails(android: androidDetails);

      await _notifications.cancelAll();

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        0,
        'ClimaSense 🌡️',
        'Ricordati di inserire i dati di oggi!',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: '❌ Errore scheduling notifica: $e',
        backgroundColor: Colors.red.shade700,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  static Future testNotification() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
    await init();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'test_channel',
      'Test ClimaSense',
      channelDescription: 'Test notifiche',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _notifications.show(
      1,
      '🔔 ClimaSense',
      'Le notifiche funzionano correttamente!',
      details,
    );
  }

  static Future cancelAll() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
    await _notifications.cancelAll();
  }
}
