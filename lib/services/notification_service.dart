// lib/services/notification_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/hive_storage.dart';
import '../utils/date_utils.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const String _fallbackTime = '20:00';

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

  static (int hour, int minute) _parseTimeStr(String? raw) {
    const fallbackHour = 20;
    const fallbackMinute = 0;

    if (raw == null || raw.trim().isEmpty) {
      return (fallbackHour, fallbackMinute);
    }

    final parts = raw.trim().split(':');
    if (parts.length != 2) return (fallbackHour, fallbackMinute);

    final hh = int.tryParse(parts[0]);
    final mm = int.tryParse(parts[1]);

    if (hh == null || mm == null) return (fallbackHour, fallbackMinute);
    if (hh < 0 || hh > 23) return (fallbackHour, fallbackMinute);
    if (mm < 0 || mm > 59) return (fallbackHour, fallbackMinute);

    return (hh, mm);
  }

  /// Verifica se l'utente ha già registrato un record oggi
  /// (per qualsiasi modalità).
  static bool _hasRecordToday() {
    final today = formatItalianDate(DateTime.now());
    final records = AppStorage.getRecords();
    return records.any((r) => r.dateIso == today);
  }

  /// Schedula il promemoria giornaliero.
  ///
  /// Comportamento smart:
  /// - Se l'utente ha già registrato i dati oggi → cancella la notifica
  ///   (non serve ricordarglielo, l'ha già fatto).
  /// - Se non ha ancora registrato → schedula normalmente.
  ///
  /// Questo metodo va chiamato:
  /// 1. All'avvio dell'app (già fatto in main.dart)
  /// 2. Dopo ogni salvataggio record (per cancellare la notifica di oggi)
  /// 3. Quando l'utente cambia l'orario nelle impostazioni
  static Future scheduleDailyReminder() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    await init();

    try {
      // Se oggi è già stato registrato, cancella la notifica pendente.
      // Il giorno dopo Android la ri-schedula automaticamente perché
      // matchDateTimeComponents: DateTimeComponents.time la ripete ogni giorno.
      if (_hasRecordToday()) {
        await _notifications.cancel(0);
        return;
      }

      final String? timeStr = AppStorage.getNotificationTime();
      final (int hh, int mm) = _parseTimeStr(timeStr ?? _fallbackTime);

      // Corpo dinamico basato sulla modalità corrente
      final modeStr = AppStorage.getSystemMode();
      final modeLabel = modeStr == 'cooling' ? 'raffrescamento' : 'riscaldamento';
      final notificationBody =
          'Non hai ancora inserito i dati di $modeLabel di oggi. Ci vorranno solo 30 secondi!';

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

      await _notifications.cancel(0);

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hh, mm);
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await _notifications.zonedSchedule(
        0,
        'ClimaSense 🌡️',
        notificationBody,
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

  /// Mostra immediatamente una notifica contestuale con il suggerimento AI.
  /// Viene chiamata dopo ogni salvataggio record, solo se l'AI ha un tip
  /// significativo (non in fase di apprendimento).
  static Future showContextualNotification({
    required String title,
    required String body,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;

    await init();

    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'contextual_channel',
        'Suggerimenti AI ClimaSense',
        channelDescription: 'Feedback intelligente dopo il salvataggio dati',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        enableVibration: false,
        playSound: false,
        // Usa un colore di sfondo teal per distinguerla dal promemoria
        color: Color(0xFF00838F),
      );
      const NotificationDetails details =
          NotificationDetails(android: androidDetails);

      await _notifications.show(
        2, // ID fisso: sovrascrive sempre la precedente notifica contestuale
        title,
        body,
        details,
      );
    } catch (e) {
      // Notifica contestuale non critica: fallisce silenziosamente
      debugPrint('NotificationService.showContextualNotification error: $e');
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
