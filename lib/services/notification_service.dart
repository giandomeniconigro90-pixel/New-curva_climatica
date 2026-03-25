// lib/services/notification_service.dart
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import '../services/hive_storage.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      tz.initializeTimeZones();

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
      );
      await _notifications.initialize(settings);

      if (Platform.isAndroid) {
        // Permesso notifiche (Android 13+)
        await Permission.notification.request();

        // Esenzione batteria — fondamentale per Samsung, Xiaomi, OnePlus, ecc.
        // Mostra un dialog di sistema che chiede all'utente di permetterlo
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } catch (e) {
      // Errore init silenzioso in produzione
    }
  }

  /// Programma la notifica giornaliera all'orario scelto dall'utente
  static Future scheduleDailyReminder() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      final stored = await AppStorage.getNotificationTime();
      final timeStr = stored ?? '21:00';
      final parts = timeStr.split(':');
      final hh = int.parse(parts[0]);
      final mm = int.parse(parts[1]);

      final now = tz.TZDateTime.now(tz.local);

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

      var dailyDate = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, hh, mm);
      if (dailyDate.isBefore(now)) {
        dailyDate = dailyDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        0,
        'ClimaSense 🌡️',
        'Ricordati di inserire i dati di oggi!',
        dailyDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      // Errore scheduling silenzioso in produzione
    }
  }

  /// Test immediato (da usare solo da UI dedicata)
  static Future testNotification() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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
