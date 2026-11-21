import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'holidays.dart';
import 'models.dart';

/// Acesso ao servidor. Abstraído para poder ser testado sem rede.
abstract class Remote {
  /// Todas as linhas do utilizador (incluindo as eliminadas logicamente).
  Future<List<Map<String, dynamic>>> fetchAll(String table);

  /// Só as linhas alteradas depois de [since].
  Future<List<Map<String, dynamic>>> fetchSince(String table, DateTime since);
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
    _ensureCorridas();
  }

  static const _tombstoneLifetime = Duration(days: 30);

  final SharedPreferences _prefs;
  final Map<String, Event> _events = {};
  final Map<String, Task> _tasks = {};
  final Map<String, EventColumn> _categories = {};
  final Map<String, WorkPage> _pages = {};

  Remote? _remote;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _fullAgain = false;
  String? lastError;

  /// Estado da sincronização. Separado dos dados, para que mudar o ícone
  /// da nuvem não obrigue a redesenhar o calendário.
  final syncStatus = ValueNotifier(SyncStatus.localOnly);

  SyncStatus get status => syncStatus.value;
  set _status(SyncStatus s) => syncStatus.value = s;

  /// Até onde já se recebeu de cada tabela (para pedir só o que mudou).
  final _cursor = <String, DateTime>{};
  DateTime? _lastFullSync;

  /// De quanto em quanto tempo se descarrega tudo (rede de segurança para
  /// relógios desacertados e eliminações definitivas).
  static const _fullSyncEvery = Duration(minutes: 15);

  /// Margem para relógios de dispositivos ligeiramente desacertados.
  static const _clockMargin = Duration(minutes: 10);

  Timer? _syncTimer;
  Timer? _persistTimer;
  final _unsaved = <String>{};

  int get pendingChanges =>
      _events.values.where((e) => e.dirty).length +
      _tasks.values.where((t) => t.dirty).length +
      _categories.values.where((c) => c.dirty).length +
      _pages.values.where((p) => p.dirty).length;

  /// Liga (ou desliga, com `null`) o servidor.
  set remote(Remote? r) {
    _remote = r;
    _cursor.clear();
    _lastFullSync = null;
    _status = r == null ? SyncStatus.localOnly : SyncStatus.syncing;
    if (r != null) sync(full: true);
  }

  // ---------------------------------------------------------------- leitura

  List<Event>? _eventsCache;
  List<Event>? _titlesCache;

  /// Um evento por título (o mais recente de cada), do mais recente para o
  /// mais antigo. Serve as sugestões ao escrever o nome de um evento.
  List<Event> get recentTitles {
    final cached = _titlesCache;
    if (cached != null) return cached;
    final now = DateTime.now();
    final byTitle = <String, Event>{};
    for (final e in _events.values) {
      if (e.isDeleted || e.title.trim().isEmpty) continue;
      // Só eventos dos últimos 2 meses (ou marcados para os próximos 2).
      final from = now.subtract(const Duration(days: 60));
      final to = now.add(const Duration(days: 60));
      final when = e.recurrence == null ? e.start : e.nextOccurrence(from);
      if (when == null || when.isBefore(from) || when.isAfter(to)) continue;
      final key = normalizeText(e.title);
      final other = byTitle[key];
      if (other == null || e.start.isAfter(other.start)) byTitle[key] = e;
    }
    return _titlesCache = byTitle.values.toList()
      ..sort((a, b) => b.start.compareTo(a.start));
  }

  /// Títulos recentes que correspondem ao que se escreveu: primeiro os que
  /// começam assim, depois os que contêm o texto.
  List<Event> suggestTitles(String typed, {int max = 6}) {
    final q = normalizeText(typed);
    if (q.isEmpty) return const [];
    final starts = <Event>[];
    final contains = <Event>[];
    for (final e in recentTitles) {
      final t = normalizeText(e.title);
      if (t == q) continue; // já está escrito
      if (t.startsWith(q)) {
        starts.add(e);
      } else if (t.contains(q)) {
        contains.add(e);
      }
      if (starts.length >= max) break;
    }
    return [...starts, ...contains].take(max).toList();
  }

  /// Todos os eventos, por data. Não alterar a lista devolvida.
  List<Event> get events =>
      _eventsCache ??= _events.values.where((e) => !e.isDeleted).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  /// Eventos por dia já calculados; esvaziado sempre que os dados mudam.
  /// Evita percorrer todos os eventos várias vezes por cada dia desenhado.
  final _dayCache = <DateTime, List<Event>>{};

  @override
  void notifyListeners() {
    _dayCache.clear();
    _eventsCache = null;
    _titlesCache = null;
    _openTasksByDay = null;
    _singleIndex = null;
    _recurring = null;
    super.notifyListeners();
  }

  /// Espera que não haja nada por enviar nem a decorrer (testes; fechar).
  Future<void> whenIdle() async {
    while ((_syncTimer?.isActive ?? false) || _syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Grava já o que estiver por gravar (ex.: a app vai fechar).
  Future<void> flush() async {
    _persistTimer?.cancel();
    await _persist();
  }

  String _keyOf(Map map) => identical(map, _events)
      ? 'events'
      : identical(map, _tasks)
      ? 'tasks'
      : identical(map, _pages)
      ? 'pages'
      : 'categories';

  void _persistSoon(Iterable<String> keys) {
    _unsaved.addAll(keys);
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 150), _persist);
  }

  /// Várias alterações seguidas dão um só envio.
  void _syncSoon() {
    if (_remote == null) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 300), sync);
  }

  /// Eventos que tocam no dia, ordenados. A lista devolvida não deve ser
  /// alterada por quem a recebe.
  List<Event> eventsOn(DateTime day) =>
      _dayCache[dateOnly(day)] ??= _computeEventsOn(day);

  /// Índice dia → eventos únicos (sem repetição), refeito quando os dados
  /// mudam. Evita percorrer todos os eventos para cada dia ao mudar de mês.
  Map<DateTime, List<Event>>? _singleIndex;
  List<Event>? _recurring;

  void _buildIndex() {
    final index = <DateTime, List<Event>>{};
    final recurring = <Event>[];
    for (final e in _events.values) {
      if (e.isDeleted) continue;
      if (e.recurrence != null) {
        recurring.add(e);
        continue;
      }
      // Cada dia em que o evento toca (no máximo um ano).
      var d = dateOnly(e.start);
      for (var i = 0; i < 366 && e.occursOn(d); i++) {
        (index[d] ??= []).add(e);
        d = DateTime(d.year, d.month, d.day + 1);
      }
    }
    _singleIndex = index;
    _recurring = recurring;
  }

  List<Event> _computeEventsOn(DateTime day) {
    if (_singleIndex == null) _buildIndex();
    final d = dateOnly(day);
    final list = [
      ...?_singleIndex![d],
      for (final e in _recurring!)
        if (e.occursOn(d)) e,
    ];
    // Feriado do dia. Se já houver um evento com o mesmo nome (ex.: vindo
    // de outro calendário), mostra-se só o feriado, com a cor dos feriados.
    final holiday = holidayOn(d);
    if (holiday != null) {
      final name = normalizeText(holiday.title);
      list
        ..removeWhere((e) => !e.multiDay && normalizeText(e.title) == name)
        ..add(holiday);
    }
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

  // ------------------------------------------------------ colunas (Eventos)

  /// Colunas da página Eventos, pela ordem em que aparecem.
  List<EventColumn> get categories =>
      _categories.values.where((c) => !c.isDeleted).toList()..sort(
        (a, b) => a.position != b.position
            ? a.position - b.position
            : a.name.compareTo(b.name),
      );

  EventColumn? categoryById(String? id) {
    final c = id == null ? null : _categories[id];
    return c == null || c.isDeleted ? null : c;
  }

  EventColumn addCategory(String name) {
    final last = categories.isEmpty ? 0 : categories.last.position + 1;
    final c = EventColumn(
      id: newId(),
      name: name,
      position: last,
      updatedAt: DateTime.now().toUtc(),
    );
    _put(_categories, c);
    return c;
  }

  void renameCategory(EventColumn c, String name) {
    c.name = name;
    _put(_categories, c);
  }

  /// Elimina a coluna; os eventos ficam no calendário, só sem coluna.
  void deleteCategory(EventColumn c) {
    for (final e in _events.values) {
      if (e.category == c.id && !e.isDeleted) {
        e.category = null;
        _put(_events, e);
      }
    }
    _put(_categories, c, delete: true);
  }

  /// A coluna "Corridas" existe sempre (a não ser que seja eliminada).
  void _ensureCorridas() {
    if (_categories.containsKey(EventColumn.corridasId)) return;
    _categories[EventColumn.corridasId] = EventColumn(
      id: EventColumn.corridasId,
      name: 'Corridas',
      // Data antiga: se já existir no servidor, a versão de lá prevalece.
      updatedAt: DateTime.utc(2026),
      dirty: true,
    );
  }

  /// Retira de uma série a ocorrência que começa em [day].
  void excludeOccurrence(Event series, DateTime day) {
    series.recurrence = series.recurrence!.excluding(day);
    saveEvent(series);
  }

  void deleteEvent(Event e) => _put(_events, e, delete: true);

  /// Desfaz uma eliminação (ou repõe um evento como estava).
  void restoreEvent(Event e, {Recurrence? recurrence}) {
    e.deletedAt = null;
    if (recurrence != null) e.recurrence = recurrence;
    _put(_events, e);
  }

  void deleteTask(Task t) => _put(_tasks, t, delete: true);

  // ------------------------------------------------------------ Workspace

  /// Páginas, pela ordem das pastas e depois da posição.
  List<WorkPage> get pages =>
      _pages.values.where((p) => !p.isDeleted).toList()..sort(
        (a, b) => a.folder != b.folder
            ? a.folder.toLowerCase().compareTo(b.folder.toLowerCase())
            : a.position != b.position
            ? a.position - b.position
            : a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );

  WorkPage? pageById(String? id) {
    final p = id == null ? null : _pages[id];
    return p == null || p.isDeleted ? null : p;
  }

  void savePage(WorkPage p) => _put(_pages, p);
  void deletePage(WorkPage p) => _put(_pages, p, delete: true);

  void restorePage(WorkPage p) {
    p.deletedAt = null;
    _put(_pages, p);
  }

  /// Muda o nome de uma pasta (em todas as páginas dela).
  void renameFolder(String from, String to) {
    for (final p in _pages.values) {
      if (!p.isDeleted && p.folder == from) {
        p.folder = to;
        _put(_pages, p);
      }
    }
  }

  /// Desfaz a eliminação de uma tarefa.
  void restoreTask(Task t) {
    t.deletedAt = null;
    _put(_tasks, t);
  }

  Map<DateTime, int>? _openTasksByDay;

  /// Tarefas por concluir com data no dia indicado.
  int openTasksOn(DateTime day) {
    final map = _openTasksByDay ??= () {
      final m = <DateTime, int>{};
      for (final t in _tasks.values) {
        if (t.isDeleted || t.done || t.due == null) continue;
        m[t.due!] = (m[t.due!] ?? 0) + 1;
      }
      return m;
    }();
    return map[dateOnly(day)] ?? 0;
  }

  /// Desloca um evento [days] dias; com [copy] cria um duplicado e mantém
  /// o original. [from] é o dia de onde foi agarrado: numa série repetida,
  /// a cópia parte dessa ocorrência e não da primeira.
  ///
  /// Numa série, só a ocorrência de [from] é afetada: ao mover, sai da série
  /// e passa a evento único no dia de destino.
  void shiftEvent(Event e, int days, {bool copy = false, DateTime? from}) {
    if (e.recurrence != null && from != null) {
      final occurrence = e.occurrenceStartOn(from) ?? dateOnly(from);
      if (!copy) excludeOccurrence(e, occurrence);
      saveEvent(
        e.occurrenceAt(
          DateTime(occurrence.year, occurrence.month, occurrence.day + days),
        ),
      );
      return;
    }
    final offset = days;
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
        recurrence: copy ? null : e.recurrence?.shifted(days),
        category: e.category,
        updatedAt: e.updatedAt,
      ),
    );
  }

  /// Ativa e futura excluem-se: marcar uma desmarca a outra.
  void toggleActive(Task t) {
    t.active = !t.active;
    if (t.active) t.future = false;
    saveTask(t);
  }

  void toggleFuture(Task t) {
    t.future = !t.future;
    if (t.future) t.active = false;
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
    _persistSoon([_keyOf(map)]);
    notifyListeners();
    _syncSoon();
  }

  // ------------------------------------------------- cópias de segurança

  /// Todos os dados, para uma cópia de segurança.
  Map<String, dynamic> exportData() => {
    'app': 'WolfCal',
    'version': 1,
    'created': DateTime.now().toUtc().toIso8601String(),
    'events': [for (final e in _events.values) e.toRemote()],
    'tasks': [for (final t in _tasks.values) t.toRemote()],
    'categories': [for (final c in _categories.values) c.toRemote()],
    'pages': [for (final p in _pages.values) p.toRemote()],
  };

  /// Repõe uma cópia: cada registo da cópia volta a ficar como estava e é
  /// enviado para o servidor como alteração nova. O que não está na cópia
  /// fica como está.
  void importData(Map<String, dynamic> data) {
    final now = DateTime.now().toUtc();
    void load<T extends Record>(
      String key,
      Map<String, T> into,
      T Function(Map<String, dynamic>) parse,
    ) {
      for (final j in (data[key] as List? ?? const [])) {
        final r = parse(Map<String, dynamic>.from(j as Map))
          ..updatedAt = now
          ..dirty = true;
        into[r.id] = r;
      }
    }

    load('events', _events, Event.fromJson);
    load('tasks', _tasks, Task.fromJson);
    load('categories', _categories, EventColumn.fromJson);
    load('pages', _pages, WorkPage.fromJson);
    _persistSoon(['events', 'tasks', 'categories', 'pages']);
    notifyListeners();
    _syncSoon();
  }

  /// Apaga a cópia local (usado ao terminar sessão).
  Future<void> clearLocal() async {
    _events.clear();
    _tasks.clear();
    _categories.clear();
    _pages.clear();
    _ensureCorridas();
    _unsaved.addAll(['events', 'tasks', 'categories', 'pages']);
    await flush();
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
    read('categories', _categories, EventColumn.fromJson);
    read('pages', _pages, WorkPage.fromJson);
  }

  Future<void> _persist() async {
    final keys = {..._unsaved};
    _unsaved.clear();
    if (keys.contains('events')) {
      await _prefs.setString(
        'events',
        jsonEncode(_events.values.map((e) => e.toLocal()).toList()),
      );
    }
    if (keys.contains('tasks')) {
      await _prefs.setString(
        'tasks',
        jsonEncode(_tasks.values.map((t) => t.toLocal()).toList()),
      );
    }
    if (keys.contains('pages')) {
      await _prefs.setString(
        'pages',
        jsonEncode(_pages.values.map((p) => p.toLocal()).toList()),
      );
    }
    if (keys.contains('categories')) {
      await _prefs.setString(
        'categories',
        jsonEncode(_categories.values.map((c) => c.toLocal()).toList()),
      );
    }
  }

  // ---------------------------------------------------------- sincronização

  /// Sincroniza com o servidor. Normalmente só pede o que mudou desde a
  /// última vez; com [full] (ou de 15 em 15 minutos) descarrega tudo.
  Future<void> sync({bool full = false}) async {
    _syncTimer?.cancel();
    final remote = _remote;
    if (remote == null) return;
    if (_syncing) {
      _syncAgain = true;
      _fullAgain |= full;
      return;
    }
    final last = _lastFullSync;
    full |= last == null || DateTime.now().difference(last) > _fullSyncEvery;
    _syncing = true;
    if (status != SyncStatus.synced) _status = SyncStatus.syncing;
    final changed = <String>{};
    try {
      // Cada tabela à parte: se uma falhar (ex.: ainda não existe no
      // servidor), as outras sincronizam na mesma.
      Object? failure;
      Future<void> table<T extends Record>(
        String name,
        Map<String, T> local,
        T Function(Map<String, dynamic>) parse,
      ) async {
        try {
          if (await _syncTable(remote, name, local, parse, full)) {
            changed.add(name);
          }
        } catch (e) {
          failure ??= e;
        }
      }

      await table('events', _events, Event.fromJson);
      await table('tasks', _tasks, Task.fromJson);
      await table('categories', _categories, EventColumn.fromJson);
      await table('pages', _pages, WorkPage.fromJson);
      if (failure != null) throw failure!;
      if (full) _lastFullSync = DateTime.now();
      lastError = null;
      if (_remote == remote) _status = SyncStatus.synced;
    } catch (e) {
      lastError = e.toString();
      if (_remote == remote) _status = SyncStatus.error;
    } finally {
      _syncing = false;
      if (changed.isNotEmpty) {
        // Só se redesenha e grava quando algo mudou de facto.
        _persistSoon(changed);
        notifyListeners();
      }
      if (_syncAgain) {
        final again = _fullAgain;
        _syncAgain = false;
        _fullAgain = false;
        unawaited(sync(full: again));
      }
    }
  }

  /// Devolve `true` se os dados locais mudaram.
  Future<bool> _syncTable<T extends Record>(
    Remote remote,
    String table,
    Map<String, T> local,
    T Function(Map<String, dynamic>) parse,
    bool full,
  ) async {
    var changed = false;
    // 1. Descarregar (tudo, ou só o que mudou) e fundir.
    final since = _cursor[table];
    final rows = full || since == null
        ? await remote.fetchAll(table)
        : await remote.fetchSince(table, since.subtract(_clockMargin));
    if (_remote != remote) return false; // sessão terminada entretanto
    final seen = <String>{};
    var newest = since;
    for (final row in rows) {
      final r = parse(row)..dirty = false;
      seen.add(r.id);
      if (newest == null || r.updatedAt.isAfter(newest)) newest = r.updatedAt;
      final mine = local[r.id];
      if (mine == null || !mine.dirty || r.updatedAt.isAfter(mine.updatedAt)) {
        if (mine == null ||
            mine.dirty ||
            mine.updatedAt != r.updatedAt ||
            mine.isDeleted != r.isDeleted) {
          changed = true;
        }
        local[r.id] = r;
      }
    }
    // Tabela vazia: a partir de agora basta pedir o que for novo.
    newest ??= full ? DateTime.now().toUtc() : null;
    if (newest != null) _cursor[table] = newest;
    if (full) {
      // O que já não existe no servidor (e não tem alterações locais) sai.
      final before = local.length;
      local.removeWhere((id, r) => !r.dirty && !seen.contains(id));
      if (local.length != before) changed = true;
    }

    // 2. Enviar alterações locais.
    final pending = local.values.where((r) => r.dirty).toList();
    if (pending.isNotEmpty) {
      final sent = {for (final r in pending) r.id: r.updatedAt};
      await remote.upsert(table, pending.map((r) => r.toRemote()).toList());
      for (final r in pending) {
        // Só fica limpo se não voltou a ser alterado durante o envio.
        if (local[r.id]?.updatedAt == sent[r.id]) r.dirty = false;
      }
      // O estado "por enviar" também é gravado localmente.
      _persistSoon([table]);
    }

    // 3. Limpeza de eliminados antigos.
    final cutoff = DateTime.now().toUtc().subtract(_tombstoneLifetime);
    if (local.values.any((r) => r.isDeleted && r.deletedAt!.isBefore(cutoff))) {
      await remote.purge(table, cutoff);
      local.removeWhere(
        (_, r) => !r.dirty && r.isDeleted && r.deletedAt!.isBefore(cutoff),
      );
    }
    return changed;
  }
}
