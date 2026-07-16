import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Recordatorios locales de tareas: programa una notificación por tarea
/// pendiente con fecha límite, a las 7:00 del día de vencimiento.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {/* fallback: UTC por defecto */}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true,
    );
    await _plugin.initialize(const InitializationSettings(android: android, iOS: darwin));

    // Permisos explícitos (iOS + Android 13+).
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('task_reminders', 'Recordatorios de tareas',
        channelDescription: 'Avisos de tareas por vencer', importance: Importance.high, priority: Priority.high),
    iOS: DarwinNotificationDetails(),
  );

  /// Reprograma todos los recordatorios a partir de las tareas del usuario.
  /// [tasks] son mapas con: id, title, crop, dueDate (yyyy-MM-dd), status.
  Future<void> scheduleTaskReminders(List<Map<String, dynamic>> tasks) async {
    if (!_ready) await init();
    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    var id = 1;
    for (final t in tasks) {
      if ((t['status'] as int? ?? 0) == 2) continue; // hecha
      final due = t['dueDate'] as String?;
      if (due == null) continue;
      final d = DateTime.tryParse(due);
      if (d == null) continue;

      // 7:00 del día de vencimiento (hora local).
      var when = tz.TZDateTime(tz.local, d.year, d.month, d.day, 7);
      if (when.isBefore(now)) continue; // no programar en el pasado

      final crop = t['crop'] as String? ?? '';
      await _plugin.zonedSchedule(
        id++,
        'Tarea por vencer${crop.isNotEmpty ? ' · $crop' : ''}',
        t['title'] as String? ?? 'Tienes una tarea pendiente',
        when,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}
