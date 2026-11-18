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
import 'task_sections.dart';

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

  /// Pedidos do widget de tarefas para abrir a página Tarefas.
  static final openTasks = ValueNotifier<int>(0);

  void init() {
    if (kIsWeb || !Platform.isAndroid) return;
    store.addListener(_soon);
    _soon();
    // A app foi aberta (ou trazida para a frente) a partir do widget.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openTab' && call.arguments == 'tasks') {
        openTasks.value++;
      }
    });
    _channel.invokeMethod<String>('launchTab').then((tab) {
      if (tab == 'tasks') openTasks.value++;
    }, onError: (_) {});
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
      await prefs.setString('widget_tasks', jsonEncode(_tasks(today)));
      await _channel.invokeMethod<void>('refresh');
    } catch (e) {
      debugPrint('Widget: $e');
    }
  }

  /// Secções de tarefas para o widget: [[nome, [[título, data, cor da
  /// prioridade (ARGB, 0 = nenhuma), atrasada (0/1)], ...]], ...].
  List<Object> _tasks(DateTime today) => [
    for (final (name, items) in taskSections(store.tasks, today))
      if (items.isNotEmpty)
        [
          name,
          [
            for (final t in items)
              [
                t.title,
                t.due == null
                    ? ''
                    : t.due == today
                    ? 'Hoje'
                    : fmtDate(t.due!),
                priorityColor(t.priority)?.toARGB32() ?? 0,
                t.due != null && t.due!.isBefore(today) ? 1 : 0,
              ],
          ],
        ],
  ];

  /// [texto, cor de fundo, cor do texto] (cores em ARGB).
  static List<Object> _event(Event e) {
    // No widget só o nome (sem horas), para caber mais.
    final color = eventColor(e.color);
    return [e.title, color.toARGB32(), onColor(color).toARGB32()];
  }
}
