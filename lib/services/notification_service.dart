// lib/services/notification_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // -----------------------------------------------------------
  // IMPOSTA QUI L'ORARIO DESIDERATO (Es. 20:00)
  // -----------------------------------------------------------
  static const int _notifyHour = 21;
  static const int _notifyMinute = 00;
  // -----------------------------------------------------------

  static Future<void> init() async {
    if (kIsWeb || Platform.isWindows) return;

    try {
      tz.initializeTimeZones();
      try { tz.setLocalLocation(tz.local); } catch (_) {}

      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
      );

      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: (details) => print("🔔 Click: ${details.payload}"),
      );

      if (Platform.isAndroid) {
        final androidImpl = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

        await androidImpl?.requestNotificationsPermission();
        // Richiedi permesso sveglie esatte (cruciale su Android 12+)
        await androidImpl?.requestExactAlarmsPermission();
      }

    } catch (e) {
      print("⚠️ ERRORE INIT NOTIFICHE: $e");
    }
  }

  // TEST MANUALE (Dal menu)
  static Future<void> showImmediateTestNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'climasense_test_manual', 'Test Manuale',
      importance: Importance.max, priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await _notifications.show(999, 'Test Manuale 🚀', 'Il sistema di notifica funziona!', details);
  }

  // SCHEDULAZIONE GIORNALIERA (All'avvio dell'app)
  static Future<void> scheduleDailyReminder() async {
    try {
      // 1. Pulisce vecchie schedulazioni per evitare duplicati
      await _notifications.cancelAll();

      // 2. Calcola la data target in modo sicuro
      final now = DateTime.now();
      DateTime targetDate = DateTime(
        now.year,
        now.month,
        now.day,
        _notifyHour,
        _notifyMinute,
      );

      // Se l'orario è già passato per oggi, programma per domani
      if (targetDate.isBefore(now)) {
        targetDate = targetDate.add(const Duration(days: 1));
      }

      // Conversione per il plugin
      final tz.TZDateTime scheduledDate = tz.TZDateTime.from(targetDate, tz.local);

      print("📅 PROSSIMA NOTIFICA PROGRAMMATA PER: $scheduledDate");

      // 3. Configura i dettagli della notifica
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'climasense_daily_final', // ID Canale Stabile
        'Promemoria Giornaliero',
        channelDescription: 'Ricorda di inserire i dati della Pompa di Calore',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const NotificationDetails details = NotificationDetails(android: androidDetails);

      // 4. Schedula la notifica ricorrente
      await _notifications.zonedSchedule(
        0, // ID Notifica
        'ClimaSense ti aspetta 🌡️',
        'Ricordati di registrare i dati di oggi!',
        scheduledDate,
        details,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Permette di svegliare il dispositivo in Doze
        matchDateTimeComponents: DateTimeComponents.time, // RIPETE OGNI GIORNO ALLA STESSA ORA
      );

      print("✅ Schedulazione completata con successo.");

    } catch (e) {
      print("⚠️ ERRORE SCHEDULAZIONE: $e");
    }
  }
}
