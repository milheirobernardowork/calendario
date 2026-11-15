import 'dart:math';

final _rng = Random.secure();

/// Gera um UUID v4.
String newId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Base comum dos registos sincronizados.
abstract class Record {
  Record({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.dirty = false,
  });

  final String id;

  /// Instante (UTC) da última alteração; em conflito ganha a mais recente.
  DateTime updatedAt;

  /// Eliminação lógica, para que a remoção se propague aos outros dispositivos.
  DateTime? deletedAt;

  /// Tem alterações locais ainda não enviadas para o servidor.
  bool dirty;

  bool get isDeleted => deletedAt != null;

  /// Colunas tal como existem na tabela remota (sem `user_id`).
  Map<String, dynamic> toRemote();

  /// Formato guardado localmente.
  Map<String, dynamic> toLocal() => {...toRemote(), 'dirty': dirty};
}

class Event extends Record {
  Event({
    required super.id,
    required this.title,
    this.notes = '',
    required this.start,
    required this.end,
    this.allDay = false,
    this.color = 0,
    required super.updatedAt,
    super.deletedAt,
    super.dirty,
  });

  String title;
  String notes;

  /// Hora local. Em eventos de dia inteiro: meia-noite do primeiro dia.
  DateTime start;

  /// Hora local. Em eventos de dia inteiro: meia-noite do último dia (inclusive).
  DateTime end;
  bool allDay;

  /// Índice em `eventColors`.
  int color;

  /// O evento toca no dia indicado?
  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    final first = dateOnly(start);
    var last = dateOnly(end);
    // Um evento que acaba exatamente à meia-noite não ocupa o dia seguinte.
    if (!allDay && end == last && end.isAfter(start)) {
      last = last.subtract(const Duration(days: 1));
    }
    return !d.isBefore(first) && !d.isAfter(last);
  }

  // Eventos de dia inteiro são gravados como meia-noite UTC da data, para
  // não mudarem de dia se o fuso horário do dispositivo mudar.
  static DateTime _decode(String s, bool allDay) {
    final t = DateTime.parse(s);
    if (!allDay) return t.toLocal();
    final u = t.toUtc();
    return DateTime(u.year, u.month, u.day);
  }

  static String _encode(DateTime t, bool allDay) => allDay
      ? DateTime.utc(t.year, t.month, t.day).toIso8601String()
      : t.toUtc().toIso8601String();

  factory Event.fromJson(Map<String, dynamic> j) {
    final allDay = j['all_day'] as bool? ?? false;
    return Event(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      start: _decode(j['start_at'] as String, allDay),
      end: _decode(j['end_at'] as String, allDay),
      allDay: allDay,
      color: (j['color'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
      deletedAt: j['deleted_at'] == null
          ? null
          : DateTime.parse(j['deleted_at'] as String).toUtc(),
      dirty: j['dirty'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toRemote() => {
    'id': id,
    'title': title,
    'notes': notes,
    'start_at': _encode(start, allDay),
    'end_at': _encode(end, allDay),
    'all_day': allDay,
    'color': color,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

class Task extends Record {
  Task({
    required super.id,
    required this.title,
    this.notes = '',
    this.due,
    this.done = false,
    this.priority = 0,
    required super.updatedAt,
    super.deletedAt,
    super.dirty,
  });

  String title;
  String notes;

  /// Data limite (só a data), opcional.
  DateTime? due;
  bool done;

  /// 0 = nenhuma, 1 = baixa, 2 = média, 3 = alta.
  int priority;

  factory Task.fromJson(Map<String, dynamic> j) {
    final due = j['due_date'] as String?;
    return Task(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      due: due == null ? null : dateOnly(DateTime.parse(due)),
      done: j['done'] as bool? ?? false,
      priority: (j['priority'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
      deletedAt: j['deleted_at'] == null
          ? null
          : DateTime.parse(j['deleted_at'] as String).toUtc(),
      dirty: j['dirty'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toRemote() => {
    'id': id,
    'title': title,
    'notes': notes,
    'due_date': due == null ? null : _ymd(due!),
    'done': done,
    'priority': priority,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
