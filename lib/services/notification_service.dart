// lib/services/notification_service.dart

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'hive_storage.dart'; // Import Hive

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      tz.initializeTimeZones();

      // Fuso orario Italia (evita l'ora indietro di 1h)
      try {
        tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      } catch (_) {}

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
      );

      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {},
      );

      if (Platform.isAndroid) {
        final androidImpl = _notifications
            .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
      }
    } catch (e) {
      print("⚠️ Errore Inizializzazione Notifiche: $e");
    }
  }

  // === SCHEDULAZIONE CON ORA DA HIVE ===
  static Future<void> scheduleDailyReminder() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      final now = tz.TZDateTime.now(tz.local);

      // Legge l'orario salvato, default 21:00
      final stored = await AppStorage.getNotificationTime();
      final parts = (stored ?? '21:00').split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      print('🔔 Ora locale: $now');
      print('🔔 Notifica programmata per: $scheduledDate');

      const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
        'daily_reminder_channel',
        'Promemoria Giornaliero',
        channelDescription:
        'Ti ricorda di inserire i dati della Pompa di Calore',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails details =
      NotificationDetails(android: androidDetails);

      await _notifications.zonedSchedule(
        0,
        'ClimaSense ti aspetta 🌡️',
        'Ricordati di registrare i dati di oggi per ottimizzare la curva!',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      print("⚠️ Errore Schedulazione Notifiche: $e");
    }
  }

  static Future<void> cancelAll() async {
    if (Platform.isWindows) return;
    await _notifications.cancelAll();
  }
}
