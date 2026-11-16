// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'screens/common.dart';
import 'store.dart';

/// Prepara os dados do widget do ecrã principal (Android).
///
/// O widget é nativo e não sabe calcular repetições nem feriados, por isso
/// a app grava já os eventos de cada dia (8 semanas para trás e ~1 ano para
/// a frente) e avisa o widget para se redesenhar.
class HomeWidgetSync {
  HomeWidgetSync(this.store, this.prefs);

  final Store store;
  final SharedPreferences prefs;

  static const _channel = MethodChannel('wolfcal/widget');
  static const _weeksBefore = 8;
  static const _weeks = 60;
  Timer? _debounce;

  void init() {
    if (kIsWeb || !Platform.isAndroid) return;
    store.addListener(_soon);
    _soon();
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _write);
  }

  static int _epochDay(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  Future<void> _write() async {
    try {
      final today = dateOnly(DateTime.now());
      final first = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1) - 7 * _weeksBefore,
      );
      final days = [
        for (var i = 0; i < _weeks * 7; i++)
          [
            for (final e in store.eventsOn(
              DateTime(first.year, first.month, first.day + i),
            ))
              _event(e),
          ],
      ];
      await prefs.setString(
        'widget_data',
        jsonEncode({'first': _epochDay(first), 'weeks': _weeks, 'days': days}),
      );
      await _channel.invokeMethod<void>('refresh');
    } catch (e) {
      debugPrint('Widget: $e');
    }
  }

  /// [texto, cor de fundo, cor do texto] (cores em ARGB).
  static List<Object> _event(Event e) {
    // No widget só o nome (sem horas), para caber mais.
    final color = eventColor(e.color);
    return [e.title, color.toARGB32(), onColor(color).toARGB32()];
  }
}
