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

  /// ✅ FIX DEFINITIVO ANDROID 13+
  static Future init() async {
    // Evita notifiche su desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      // Timezone
      tz.initializeTimeZones();

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
      );
      await _notifications.initialize(settings);

      // ✅ PERMESSO ROBUSTO Android 13+
      if (Platform.isAndroid) {
        final PermissionStatus status = await Permission.notification.request();
        print('🔔 Permesso notifica: $status');
        if (status.isGranted) {
          print('✅ Permesso NOTIFICHE CONCESSO');
        } else {
          print('❌ Permesso NOTIFICHE NEGATO - Vai in Impostazioni > App > ClimaSense > Notifiche');
        }
      }

      print('🔔 Notifiche inizializzate ✅');
    } catch (e) {
      print('⚠️ Errore init notifiche: $e');
    }
  }

  /// Programma: TEST tra 2 minuti + giornaliero
  static Future scheduleDailyReminder() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      final stored = await AppStorage.getNotificationTime();
      final timeStr = stored ?? '21:00';
      final parts = timeStr.split(':');
      final hh = int.parse(parts[0]);
      final mm = int.parse(parts[1]);

      final now = tz.TZDateTime.now(tz.local);
      print('🕐 Orario Hive: $timeStr - now: ${now.hour}:${now.minute}');

      // TEST tra 2 minuti
      final testTime = now.add(const Duration(minutes: 2));
      print('🧪 TEST programmato per ${testTime.hour}:${testTime.minute}:${testTime.second}');

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
      const NotificationDetails details = NotificationDetails(android: androidDetails);

      // Pulisci precedenti
      await _notifications.cancelAll();

      // 1) Test dopo 2 minuti
      await _notifications.zonedSchedule(
        999,
        '🧪 PROVA 2 MINUTI',
        'Se vedi questa notifica, lo scheduling funziona!',
        testTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );

      // 2) Notifica giornaliera
      var dailyDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
      if (dailyDate.isBefore(now)) {
        dailyDate = dailyDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        0,
        'ClimaSense 🌡️ $timeStr',
        'Ricordati di inserire i dati di oggi!',
        dailyDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      print(
          '✅ Programmate: TEST @ ${testTime.hour}:${testTime.minute}, DAILY @ ${dailyDate.day}/${dailyDate.month} ${dailyDate.hour}:${dailyDate.minute}');
    } catch (e) {
      print('❌ Errore scheduleDailyReminder: $e');
    }
  }

  /// Test immediato (Menu → "TEST Notifica ORA")
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
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      1,
      '🧪 TEST NOTIFICA',
      'Se vedi questa, tutto è configurato correttamente.',
      details,
    );
    print('🔔 TEST immediato inviato ✅');
  }

  static Future cancelAll() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
    await _notifications.cancelAll();
    print('🔔 Tutte le notifiche cancellate');
  }
}
