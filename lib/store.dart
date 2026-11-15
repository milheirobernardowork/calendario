import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Acesso ao servidor. Abstraído para poder ser testado sem rede.
abstract class Remote {
  /// Todas as linhas do utilizador (incluindo as eliminadas logicamente).
  Future<List<Map<String, dynamic>>> fetchAll(String table);
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// Remove definitivamente linhas eliminadas antes de [before].
  Future<void> purge(String table, DateTime before);
}

enum SyncStatus { localOnly, synced, syncing, error }

/// Dados da app: cópia local (funciona offline) + sincronização.
///
/// Estratégia: cada alteração é gravada localmente e marcada como `dirty`.
/// Ao sincronizar, descarrega-se o estado remoto, resolve-se cada conflito a
/// favor da alteração mais recente (`updatedAt`) e enviam-se as pendentes.
class Store extends ChangeNotifier {
  Store(this._prefs) {
    _load();
  }

  static const _tombstoneLifetime = Duration(days: 30);

  final SharedPreferences _prefs;
  final Map<String, Event> _events = {};
  final Map<String, Task> _tasks = {};

  Remote? _remote;
  bool _syncing = false;
  bool _syncAgain = false;
  SyncStatus _status = SyncStatus.localOnly;
  String? lastError;

  SyncStatus get status => _status;

  int get pendingChanges =>
      _events.values.where((e) => e.dirty).length +
      _tasks.values.where((t) => t.dirty).length;

  /// Liga (ou desliga, com `null`) o servidor.
  set remote(Remote? r) {
    _remote = r;
    _status = r == null ? SyncStatus.localOnly : SyncStatus.syncing;
    notifyListeners();
    if (r != null) sync();
  }

  // ---------------------------------------------------------------- leitura

  List<Event> get events =>
      _events.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  /// Eventos por dia já calculados; esvaziado sempre que os dados mudam.
  /// Evita percorrer todos os eventos várias vezes por cada dia desenhado.
  final _dayCache = <DateTime, List<Event>>{};

  @override
  void notifyListeners() {
    _dayCache.clear();
    super.notifyListeners();
  }

  /// Eventos que tocam no dia, ordenados. A lista devolvida não deve ser
  /// alterada por quem a recebe.
  List<Event> eventsOn(DateTime day) =>
      _dayCache[dateOnly(day)] ??= _computeEventsOn(day);

  List<Event> _computeEventsOn(DateTime day) {
    final list = _events.values
        .where((e) => !e.isDeleted && e.occursOn(day))
        .toList();
    list.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      // Pela hora do dia: numa série, a data de início é a da 1.ª ocorrência.
      final ta = a.start.hour * 60 + a.start.minute;
      final tb = b.start.hour * 60 + b.start.minute;
      return ta != tb ? ta - tb : a.title.compareTo(b.title);
    });
    return list;
  }

  List<Task> get tasks => _tasks.values.where((t) => !t.isDeleted).toList();

  // ---------------------------------------------------------------- escrita

  void saveEvent(Event e) => _put(_events, e);
  void saveTask(Task t) => _put(_tasks, t);

  void deleteEvent(Event e) => _put(_events, e, delete: true);
  void deleteTask(Task t) => _put(_tasks, t, delete: true);

  /// Desloca um evento [days] dias; com [copy] cria um duplicado e mantém
  /// o original. [from] é o dia de onde foi agarrado: numa série repetida,
  /// a cópia parte dessa ocorrência e não da primeira.
  void shiftEvent(Event e, int days, {bool copy = false, DateTime? from}) {
    var offset = days;
    if (copy && e.recurrence != null && from != null) {
      offset += daysBetween(e.start, from);
    }
    DateTime shift(DateTime t) =>
        DateTime(t.year, t.month, t.day + offset, t.hour, t.minute);
    saveEvent(
      Event(
        id: copy ? newId() : e.id,
        title: e.title,
        notes: e.notes,
        start: shift(e.start),
        end: shift(e.end),
        allDay: e.allDay,
        color: e.color,
        // Mover desloca a série inteira; a cópia é um evento único.
        recurrence: copy ? null : e.recurrence?.shifted(days),
        updatedAt: e.updatedAt,
      ),
    );
  }

  void toggleActive(Task t) {
    t.active = !t.active;
    saveTask(t);
  }

  void toggleTask(Task t) {
    t.done = !t.done;
    saveTask(t);
  }

  void _put<T extends Record>(Map<String, T> map, T r, {bool delete = false}) {
    final now = DateTime.now().toUtc();
    r.updatedAt = now;
    if (delete) r.deletedAt = now;
    r.dirty = true;
    map[r.id] = r;
    _persist();
    notifyListeners();
    sync();
  }

  /// Apaga a cópia local (usado ao terminar sessão).
  Future<void> clearLocal() async {
    _events.clear();
    _tasks.clear();
    await _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------- armazenamento

  void _load() {
    void read<T extends Record>(
      String key,
      Map<String, T> into,
      T Function(Map<String, dynamic>) parse,
    ) {
      final raw = _prefs.getString(key);
      if (raw == null) return;
      try {
        for (final j in jsonDecode(raw) as List) {
          final r = parse(Map<String, dynamic>.from(j as Map));
          into[r.id] = r;
        }
      } catch (e) {
        debugPrint('Dados locais inválidos em "$key": $e');
      }
    }

    read('events', _events, Event.fromJson);
    read('tasks', _tasks, Task.fromJson);
  }

  Future<void> _persist() async {
    await _prefs.setString(
      'events',
      jsonEncode(_events.values.map((e) => e.toLocal()).toList()),
    );
    await _prefs.setString(
      'tasks',
      jsonEncode(_tasks.values.map((t) => t.toLocal()).toList()),
    );
  }

  // ---------------------------------------------------------- sincronização

  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      await _syncTable(remote, 'events', _events, Event.fromJson);
      await _syncTable(remote, 'tasks', _tasks, Task.fromJson);
      lastError = null;
      if (_remote == remote) _status = SyncStatus.synced;
    } catch (e) {
      lastError = e.toString();
      if (_remote == remote) _status = SyncStatus.error;
    } finally {
      _syncing = false;
      await _persist();
      notifyListeners();
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(sync());
      }
    }
  }

  Future<void> _syncTable<T extends Record>(
    Remote remote,
    String table,
    Map<String, T> local,
    T Function(Map<String, dynamic>) parse,
  ) async {
    // 1. Descarregar e fundir.
    final rows = await remote.fetchAll(table);
    if (_remote != remote) return; // sessão terminada entretanto
    final seen = <String>{};
    for (final row in rows) {
      final r = parse(row)..dirty = false;
      seen.add(r.id);
      final mine = local[r.id];
      if (mine == null || !mine.dirty || r.updatedAt.isAfter(mine.updatedAt)) {
        local[r.id] = r;
      }
    }
    // O que já não existe no servidor (e não tem alterações locais) sai.
    local.removeWhere((id, r) => !r.dirty && !seen.contains(id));

    // 2. Enviar alterações locais.
    final pending = local.values.where((r) => r.dirty).toList();
    if (pending.isNotEmpty) {
      final sent = {for (final r in pending) r.id: r.updatedAt};
      await remote.upsert(table, pending.map((r) => r.toRemote()).toList());
      for (final r in pending) {
        // Só fica limpo se não voltou a ser alterado durante o envio.
        if (local[r.id]?.updatedAt == sent[r.id]) r.dirty = false;
      }
    }

    // 3. Limpeza de eliminados antigos.
    final cutoff = DateTime.now().toUtc().subtract(_tombstoneLifetime);
    if (local.values.any((r) => r.isDeleted && r.deletedAt!.isBefore(cutoff))) {
      await remote.purge(table, cutoff);
      local.removeWhere(
        (_, r) => !r.dirty && r.isDeleted && r.deletedAt!.isBefore(cutoff),
      );
    }
  }
}
