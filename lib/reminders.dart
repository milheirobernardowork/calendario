import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'holidays.dart';
import 'models.dart';
import 'store.dart';

/// Lembretes 15 minutos antes de cada evento com hora.
///
/// São agendados no sistema (Android / Windows), por isso aparecem mesmo
/// com a app fechada. Sempre que os dados mudam, refaz-se a lista para os
/// próximos [_horizon] dias.
class Reminders {
  Reminders(this.store);

  final Store store;
  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _debounce;
  var _exact = false;

  static const _lead = Duration(minutes: 15);
  static const _horizon = 30; // dias
  static const _max = 150; // o Android aceita até 500 alarmes por app

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  Future<void> init() async {
    if (!supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'WolfCal',
            appUserModelId: 'WolfCal.WolfCal',
            guid: '5f3b8d4e-2c1a-4e7b-9a6d-0c8e1f2b3a47',
          ),
        ),
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        await android.requestNotificationsPermission();
        _exact = await android.canScheduleExactNotifications() ?? false;
      }
      store.addListener(_soon);
      _soon();
    } catch (e) {
      debugPrint('Notificações indisponíveis: $e');
    }
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _reschedule);
  }

  Future<void> _reschedule() async {
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      final today = dateOnly(now);
      final due = <({DateTime at, DateTime start, Event event})>[];
      for (var i = 0; i < _horizon; i++) {
        final day = DateTime(today.year, today.month, today.day + i);
        for (final e in store.eventsOn(day)) {
          if (e.allDay || e.isHoliday || !e.startsOn(day)) continue;
          final start = DateTime(
            day.year,
            day.month,
            day.day,
            e.start.hour,
            e.start.minute,
          );
          final at = start.subtract(_lead);
          if (at.isAfter(now)) due.add((at: at, start: start, event: e));
        }
      }
      due.sort((a, b) => a.at.compareTo(b.at));
      var id = 0;
      for (final r in due.take(_max)) {
        final hh = r.start.hour.toString().padLeft(2, '0');
        final mm = r.start.minute.toString().padLeft(2, '0');
        await _plugin.zonedSchedule(
          id: id++,
          title: r.event.title,
          body: 'Começa daqui a 15 minutos, às $hh:$mm',
          scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'lembretes',
              'Lembretes de eventos',
              channelDescription: '15 minutos antes de cada evento',
              importance: Importance.high,
              priority: Priority.high,
            ),
            windows: WindowsNotificationDetails(),
          ),
          androidScheduleMode: _exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Falha ao agendar lembretes: $e');
    }
  }
}
