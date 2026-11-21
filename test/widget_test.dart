import 'dart:convert';

import 'package:agenda/holidays.dart';
import 'package:agenda/models.dart';
import 'package:agenda/store.dart';
import 'package:agenda/updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servidor em memória partilhado por vários "dispositivos".
class FakeRemote implements Remote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  bool offline = false;

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async {
    if (offline) throw Exception('offline');
    fullFetches++;
    return (tables[table] ?? {}).values.map((r) => {...r}).toList();
  }

  int fullFetches = 0;
  int partialFetches = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchSince(
    String table,
    DateTime since,
  ) async {
    if (offline) throw Exception('offline');
    partialFetches++;
    return (tables[table] ?? {}).values
        .where((r) => DateTime.parse(r['updated_at'] as String).isAfter(since))
        .map((r) => {...r})
        .toList();
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (offline) throw Exception('offline');
    final t = tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      t[r['id'] as String] = {...r};
    }
  }

  @override
  Future<void> purge(String table, DateTime before) async {
    tables[table]?.removeWhere((_, r) {
      final d = r['deleted_at'] as String?;
      return d != null && DateTime.parse(d).isBefore(before);
    });
  }
}

Future<Store> device(Remote? remote) async {
  SharedPreferences.setMockInitialValues({});
  final s = Store(await SharedPreferences.getInstance());
  if (remote != null) {
    s.remote = remote;
    await settle(s);
  }
  return s;
}

/// Espera que as sincronizações em curso terminem.
Future<void> settle(Store s) => s.whenIdle();

Task task(String title) =>
    Task(id: newId(), title: title, updatedAt: DateTime.now().toUtc());

void main() {
  dragTests();
  recurrenceTests();
  taskFlagTests();
  syncEfficiencyTests();
  suggestionTests();
  holidayTests();
  updateTests();
  workspaceTests();
  backupTests();
  test('alterações propagam-se entre dispositivos', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);

    final t = task('Comprar pão');
    pc.saveTask(t);
    pc.saveEvent(
      Event(
        id: newId(),
        title: 'Dentista',
        start: DateTime(2026, 11, 20, 10),
        end: DateTime(2026, 11, 20, 11),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await settle(pc);
    await phone.sync();

    expect(phone.tasks.single.title, 'Comprar pão');
    expect(phone.eventsOn(DateTime(2026, 11, 20)).single.title, 'Dentista');
    expect(phone.events.single.start, DateTime(2026, 11, 20, 10));

    // Concluir no telemóvel reflete-se no PC.
    phone.toggleTask(phone.tasks.single);
    await settle(phone);
    await pc.sync();
    expect(pc.tasks.single.done, isTrue);

    // Eliminar no PC remove no telemóvel.
    pc.deleteTask(pc.tasks.single);
    await settle(pc);
    await phone.sync();
    expect(phone.tasks, isEmpty);
  });

  test('offline: guarda localmente e envia quando há rede', () async {
    final server = FakeRemote()..offline = true;
    final phone = await device(server);
    phone.saveTask(task('Offline'));
    await settle(phone);
    expect(phone.status, SyncStatus.error);
    expect(phone.pendingChanges, 2); // a tarefa + a coluna "Corridas"
    expect(phone.tasks, hasLength(1));

    server.offline = false;
    await phone.sync();
    expect(phone.status, SyncStatus.synced);
    expect(phone.pendingChanges, 0);
    expect(server.tables['tasks'], hasLength(1));
  });

  test('conflito: ganha a alteração mais recente', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    pc.saveTask(task('Original'));
    await settle(pc);
    await phone.sync();

    server.offline = true;
    phone.saveTask(phone.tasks.single..title = 'Do telemóvel');
    await settle(phone);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    server.offline = false;
    pc.saveTask(pc.tasks.single..title = 'Do PC (mais recente)');
    await settle(pc);

    await phone.sync();
    await pc.sync();
    expect(phone.tasks.single.title, 'Do PC (mais recente)');
    expect(pc.tasks.single.title, 'Do PC (mais recente)');
    expect(phone.pendingChanges, 0);
  });

  test('evento de dia inteiro mantém a data e cobre vários dias', () {
    final e = Event(
      id: newId(),
      title: 'Férias',
      start: DateTime(2026, 8, 1),
      end: DateTime(2026, 8, 3),
      allDay: true,
      updatedAt: DateTime.now().toUtc(),
    );
    final back = Event.fromJson(e.toRemote());
    expect(back.start, DateTime(2026, 8, 1));
    expect(back.end, DateTime(2026, 8, 3));
    expect(back.occursOn(DateTime(2026, 8, 2, 15)), isTrue);
    expect(back.occursOn(DateTime(2026, 8, 4)), isFalse);
    expect(back.occursOn(DateTime(2026, 7, 31)), isFalse);
  });

  test('dados locais sobrevivem a reiniciar a app', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final a = Store(prefs)..saveTask(task('Persistente'));
    await a.flush();
    expect(a.tasks, hasLength(1));
    final b = Store(prefs);
    expect(b.tasks.single.title, 'Persistente');
    expect(b.pendingChanges, 2); // a tarefa + a coluna "Corridas"
  });
}

// Arrastar um evento no calendário: mover ou copiar.
void dragTests() {
  Event sample() => Event(
    id: newId(),
    title: 'Reunião',
    start: DateTime(2026, 11, 30, 10),
    end: DateTime(2026, 11, 30, 11, 30),
    color: 2,
    updatedAt: DateTime.now().toUtc(),
  );

  test('mover evento muda o dia e mantém a hora', () async {
    final s = await device(null);
    final e = sample();
    s.saveEvent(e);
    s.shiftEvent(e, 2);
    expect(s.events.single.id, e.id);
    expect(s.events.single.start, DateTime(2026, 12, 2, 10));
    expect(s.events.single.end, DateTime(2026, 12, 2, 11, 30));
    expect(s.eventsOn(DateTime(2026, 11, 30)), isEmpty);
  });

  test('copiar evento mantém o original', () async {
    final s = await device(null);
    final e = sample();
    s.saveEvent(e);
    s.shiftEvent(e, -3, copy: true);
    expect(s.events, hasLength(2));
    expect(s.eventsOn(DateTime(2026, 11, 30)).single.id, e.id);
    final copy = s.eventsOn(DateTime(2026, 11, 27)).single;
    expect(copy.id, isNot(e.id));
    expect(copy.title, 'Reunião');
    expect(copy.color, 2);
  });
}

// Eventos repetidos.
void recurrenceTests() {
  Event weekly(Recurrence r, {DateTime? start}) => Event(
    id: newId(),
    title: 'Ginásio',
    start: start ?? DateTime(2026, 11, 16, 7, 30), // segunda-feira
    end: (start ?? DateTime(2026, 11, 16, 7, 30)).add(const Duration(hours: 1)),
    recurrence: r,
    updatedAt: DateTime.now().toUtc(),
  );

  test('semanal em dias escolhidos, a cada 2 semanas', () {
    final e = weekly(
      const Recurrence(unit: 'week', interval: 2, weekdays: {1, 3, 5}),
    );
    expect(e.occursOn(DateTime(2026, 11, 16)), isTrue); // seg
    expect(e.occursOn(DateTime(2026, 11, 17)), isFalse); // ter
    expect(e.occursOn(DateTime(2026, 11, 18)), isTrue); // qua
    expect(e.occursOn(DateTime(2026, 11, 20)), isTrue); // sex
    expect(e.occursOn(DateTime(2026, 11, 23)), isFalse); // semana seguinte
    expect(e.occursOn(DateTime(2026, 11, 30)), isTrue); // 2 semanas depois
    expect(e.occursOn(DateTime(2026, 11, 9)), isFalse); // antes do início
  });

  test('termina após N vezes ou numa data', () {
    final byCount = weekly(
      const Recurrence(unit: 'week', weekdays: {1, 3}, count: 3),
    );
    expect(byCount.occursOn(DateTime(2026, 11, 16)), isTrue); // 1.ª
    expect(byCount.occursOn(DateTime(2026, 11, 18)), isTrue); // 2.ª
    expect(byCount.occursOn(DateTime(2026, 11, 23)), isTrue); // 3.ª
    expect(byCount.occursOn(DateTime(2026, 11, 25)), isFalse);

    final byDate = weekly(
      Recurrence(unit: 'day', interval: 2, until: DateTime(2026, 11, 20)),
    );
    expect(byDate.occursOn(DateTime(2026, 11, 18)), isTrue);
    expect(byDate.occursOn(DateTime(2026, 11, 19)), isFalse);
    expect(byDate.occursOn(DateTime(2026, 11, 20)), isTrue);
    expect(byDate.occursOn(DateTime(2026, 11, 22)), isFalse);
  });

  test('mensal e anual', () {
    final monthly = weekly(
      const Recurrence(unit: 'month'),
      start: DateTime(2026, 1, 29, 9),
    );
    expect(monthly.occursOn(DateTime(2026, 3, 29)), isTrue);
    expect(monthly.occursOn(DateTime(2026, 3, 28)), isFalse);
    final yearly = weekly(
      const Recurrence(unit: 'year'),
      start: DateTime(2026, 12, 10),
    );
    expect(yearly.occursOn(DateTime(2028, 12, 10)), isTrue);
    expect(yearly.occursOn(DateTime(2028, 12, 11)), isFalse);
  });

  test('a repetição sobrevive à sincronização', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    pc.saveEvent(
      weekly(const Recurrence(unit: 'week', weekdays: {2, 4}, count: 8)),
    );
    await settle(pc);
    await phone.sync();
    final r = phone.events.single.recurrence!;
    expect(r.unit, 'week');
    expect(r.weekdays, {2, 4});
    expect(r.count, 8);
    expect(phone.eventsOn(DateTime(2026, 11, 19)), hasLength(1)); // quinta
    expect(phone.eventsOn(DateTime(2026, 11, 20)), isEmpty);
  });

  test('mover ou copiar só afeta a ocorrência desse dia', () async {
    final s = await device(null);
    final e = weekly(const Recurrence(unit: 'week', weekdays: {1}));
    s.saveEvent(e);
    // Copiar a ocorrência de 30 nov para 2 dez.
    s.shiftEvent(e, 2, copy: true, from: DateTime(2026, 11, 30));
    expect(s.eventsOn(DateTime(2026, 12, 2)).single.recurrence, isNull);
    expect(s.eventsOn(DateTime(2026, 11, 30)).single.id, e.id);
    // Mover a ocorrência de 23 nov para dia 24.
    s.shiftEvent(e, 1, from: DateTime(2026, 11, 23));
    expect(s.eventsOn(DateTime(2026, 11, 23)), isEmpty);
    final moved = s.eventsOn(DateTime(2026, 11, 24)).single;
    expect(moved.id, isNot(e.id));
    expect(moved.start, DateTime(2026, 11, 24, 7, 30));
    // O resto da série fica igual.
    expect(s.eventsOn(DateTime(2026, 11, 16)).single.id, e.id);
    expect(s.eventsOn(DateTime(2026, 12, 7)).single.id, e.id);
  });

  test('ocorrência retirada sincroniza e conta para o total', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    final e = weekly(const Recurrence(unit: 'week', weekdays: {1}, count: 3));
    pc.saveEvent(e);
    pc.excludeOccurrence(e, DateTime(2026, 11, 23));
    await settle(pc);
    await phone.sync();
    final p = phone.events.single;
    expect(p.occursOn(DateTime(2026, 11, 16)), isTrue);
    expect(p.occursOn(DateTime(2026, 11, 23)), isFalse);
    expect(p.occursOn(DateTime(2026, 11, 30)), isTrue);
    expect(p.occursOn(DateTime(2026, 12, 7)), isFalse);
    expect(p.nextOccurrence(DateTime(2026, 11, 17)), DateTime(2026, 11, 30));
  });

  test('colunas de Eventos: Corridas existe e sincroniza', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    expect(pc.categories.single.id, EventColumn.corridasId);
    final race = Event(
      id: newId(),
      title: 'Meia Maratona dos Descobrimentos',
      start: DateTime(2026, 11, 29, 10),
      end: DateTime(2026, 11, 29, 12),
      category: EventColumn.corridasId,
      updatedAt: DateTime.now().toUtc(),
    );
    pc.saveEvent(race);
    pc.addCategory('Viagens');
    await settle(pc);
    await phone.sync();
    expect(phone.categories.map((c) => c.name), ['Corridas', 'Viagens']);
    expect(phone.events.single.category, EventColumn.corridasId);
    expect(server.tables['categories'], hasLength(2));
  });
}

void taskFlagTests() {
  test('futura, ativa e data de criação sincronizam', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    final created = DateTime.utc(2026, 11, 1, 9);
    final t = Task(
      id: newId(),
      title: 'Renovar passaporte',
      createdAt: created,
      updatedAt: DateTime.now().toUtc(),
    );
    pc.saveTask(t);
    pc.toggleActive(t);
    pc.toggleFuture(t); // marcar futura desmarca ativa
    await settle(pc);
    await phone.sync();
    final p = phone.tasks.single;
    expect(p.future, isTrue);
    expect(p.active, isFalse);
    expect(p.createdAt, created);
    expect(p.due, isNull);
  });
}

void syncEfficiencyTests() {
  test('depois da primeira, a sincronização só pede o que mudou', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    final fullBefore = server.fullFetches;
    pc.saveTask(task('Nova'));
    await settle(pc);
    await phone.sync();
    expect(phone.tasks.single.title, 'Nova');
    expect(server.fullFetches, fullBefore); // nada de descarregar tudo
    expect(server.partialFetches, greaterThan(0));
    // Forçar uma sincronização completa continua a funcionar.
    await phone.sync(full: true);
    expect(server.fullFetches, greaterThan(fullBefore));
  });

  test('várias alterações seguidas dão um só envio', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final before = server.partialFetches + server.fullFetches;
    for (var i = 0; i < 5; i++) {
      pc.saveTask(task('T$i'));
    }
    await settle(pc);
    // Uma sincronização = 4 tabelas.
    expect(server.partialFetches + server.fullFetches - before, 4);
    expect(server.tables['tasks'], hasLength(5));
  });
}

void suggestionTests() {
  test('sugestões de títulos: recentes, sem acentos, sem repetidos', () async {
    final s = await device(null);
    Event ev(String title, DateTime start) => Event(
      id: newId(),
      title: title,
      start: start,
      end: start.add(const Duration(hours: 1)),
      updatedAt: DateTime.now().toUtc(),
    );
    final now = DateTime.now();
    s.saveEvent(ev('Ginásio 💪', now.subtract(const Duration(days: 3))));
    s.saveEvent(ev('Ginásio 💪', now.subtract(const Duration(days: 1))));
    s.saveEvent(ev('Jantar Nena', now.subtract(const Duration(days: 2))));
    s.saveEvent(ev('Reunião Ginásio', now.subtract(const Duration(days: 5))));
    s.saveEvent(ev('Gin muito no futuro', now.add(const Duration(days: 400))));
    s.saveEvent(ev('Ginástica antiga', now.subtract(const Duration(days: 90))));
    final r = s.suggestTitles('gina');
    expect(r.map((e) => e.title), ['Ginásio 💪', 'Reunião Ginásio']);
    expect(r.first.start.day, now.subtract(const Duration(days: 1)).day);
    expect(s.suggestTitles(''), isEmpty);
    expect(s.suggestTitles('jan').single.title, 'Jantar Nena');
  });
}

void holidayTests() {
  test('feriados de Portugal: Páscoa e datas móveis', () {
    expect(easter(2026), DateTime(2026, 4, 5));
    expect(easter(2027), DateTime(2027, 3, 28));
    final h = portugueseHolidays(2026);
    expect(h[DateTime(2026, 4, 3)], 'Sexta-feira Santa');
    expect(h[DateTime(2026, 6, 4)], 'Corpo de Deus');
    expect(h[DateTime(2026, 2, 17)], 'Carnaval');
    expect(h[DateTime(2026, 4, 25)], 'Dia da Liberdade');
    expect(h, hasLength(14));
    // Datas móveis certas em cada ano (Sexta-feira Santa e Corpo de Deus).
    expect(
      portugueseHolidays(2027)[DateTime(2027, 3, 26)],
      'Sexta-feira Santa',
    );
    expect(portugueseHolidays(2027)[DateTime(2027, 5, 27)], 'Corpo de Deus');
    expect(easter(2028), DateTime(2028, 4, 16));
    expect(
      portugueseHolidays(2028)[DateTime(2028, 4, 14)],
      'Sexta-feira Santa',
    );
    expect(portugueseHolidays(2028)[DateTime(2028, 6, 15)], 'Corpo de Deus');
  });

  test('feriado aparece no dia, verde escuro, sem duplicar', () async {
    final s = await device(null);
    final day = DateTime(2026, 12, 8);
    final h = s.eventsOn(day).single;
    expect(h.isHoliday, isTrue);
    expect(h.title, 'Imaculada Conceição');
    expect(h.color, holidayColor);
    expect(s.events, isEmpty); // não é gravado
    // Se já houver um evento com o mesmo nome, aparece só o feriado.
    s.saveEvent(
      Event(
        id: newId(),
        title: 'Dia de Natal',
        start: DateTime(2026, 12, 25),
        end: DateTime(2026, 12, 25),
        allDay: true,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    expect(s.eventsOn(DateTime(2026, 12, 25)).single.isHoliday, isTrue);
  });

  test('eliminar e anular', () async {
    final s = await device(null);
    final e = Event(
      id: newId(),
      title: 'Reunião',
      start: DateTime(2026, 11, 20, 10),
      end: DateTime(2026, 11, 20, 11),
      updatedAt: DateTime.now().toUtc(),
    );
    s.saveEvent(e);
    s.deleteEvent(e);
    expect(s.events, isEmpty);
    s.restoreEvent(e);
    expect(s.events.single.id, e.id);
  });
}

void updateTests() {
  test('comparar versões', () {
    expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareVersions('v1.0.14', '1.0.14'), 0);
    expect(compareVersions('1.0.14', '1.1.0'), lessThan(0));
    expect(compareVersions('1.0.15', '1.0.14+14'), greaterThan(0));
  });
}

void workspaceTests() {
  test('páginas do Workspace sincronizam com blocos e tabelas', () async {
    final server = FakeRemote();
    final pc = await device(server);
    final phone = await device(server);
    final page = WorkPage(
      id: newId(),
      title: 'Erasmus',
      folder: 'ATEC',
      color: 2,
      blocks: [
        {'id': newId(), 'type': 'h1', 'text': 'Calendário'},
        {
          'id': newId(),
          'type': 'table',
          'rows': [
            ['Turmas', 'Início'],
            ['TEAI + ARMI', '01 Fev'],
          ],
        },
        {'id': newId(), 'type': 'todo', 'text': 'Enviar mail', 'checked': true},
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    pc.savePage(page);
    await settle(pc);
    await phone.sync();
    final p = phone.pages.single;
    expect(p.title, 'Erasmus');
    expect(p.folder, 'ATEC');
    expect((p.blocks[1]['rows'] as List)[1], ['TEAI + ARMI', '01 Fev']);
    expect(p.blocks[2]['checked'], isTrue);
    phone.renameFolder('ATEC', 'ATEC 2026');
    await settle(phone);
    await pc.sync();
    expect(pc.pages.single.folder, 'ATEC 2026');
  });
}

void backupTests() {
  test('cópia de segurança: exportar e repor', () async {
    final s = await device(null);
    final t = task('Pagar seguro');
    s.saveTask(t);
    final data = jsonDecode(jsonEncode(s.exportData())) as Map<String, dynamic>;
    s.deleteTask(t);
    expect(s.tasks, isEmpty);
    s.importData(data);
    expect(s.tasks.single.title, 'Pagar seguro');
    expect(s.pendingChanges, greaterThan(0)); // vai para o servidor
  });
}
