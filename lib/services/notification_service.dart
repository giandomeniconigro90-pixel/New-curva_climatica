// lib/services/notification_service.dart

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // 1. Esci se siamo su Desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      // 2. Inizializza Timezone
      tz.initializeTimeZones();

      // 3. Configura Android
      // IMPORTANTE: Assicurati che l'icona 'ic_launcher' esista in android/app/src/main/res/mipmap-*/
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
      );

      // 4. Inizializza Plugin (con gestione errore)
      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Qui gestisci il click sulla notifica (opzionale)
        },
      );

      // 5. Richiedi Permessi (Solo Android 13+)
      if (Platform.isAndroid) {
        final androidImpl = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        await androidImpl?.requestNotificationsPermission();
      }

    } catch (e) {
      // Se qualcosa fallisce, logghiamo ma NON FACCIAMO CRASHARE L'APP
      print("⚠️ Errore Inizializzazione Notifiche: $e");
    }
  }

  static Future<void> scheduleDailyReminder() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 00);

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'daily_reminder_channel',
        'Promemoria Giornaliero',
        channelDescription: 'Ti ricorda di inserire i dati della Pompa di Calore',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails details = NotificationDetails(android: androidDetails);

      await _notifications.zonedSchedule(
        0,
        'ClimaSense ti aspetta 🌡️',
        'Ricordati di registrare i dati di oggi per ottimizzare la curva!',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
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
