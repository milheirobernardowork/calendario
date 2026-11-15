import 'package:agenda/models.dart';
import 'package:agenda/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servidor em memória partilhado por vários "dispositivos".
class FakeRemote implements Remote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  bool offline = false;

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async {
    if (offline) throw Exception('offline');
    return (tables[table] ?? {}).values.map((r) => {...r}).toList();
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
Future<void> settle(Store s) async {
  for (var i = 0; i < 50 && s.status == SyncStatus.syncing; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Task task(String title) =>
    Task(id: newId(), title: title, updatedAt: DateTime.now().toUtc());

void main() {
  dragTests();
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
    expect(phone.pendingChanges, 1);
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
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(a.tasks, hasLength(1));
    final b = Store(prefs);
    expect(b.tasks.single.title, 'Persistente');
    expect(b.pendingChanges, 1);
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
