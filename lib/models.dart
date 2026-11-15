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

/// Dias de calendário entre duas datas (ignora horas e mudanças de hora).
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Regra de repetição de um evento.
class Recurrence {
  const Recurrence({
    required this.unit,
    this.interval = 1,
    this.weekdays = const {},
    this.until,
    this.count,
  });

  /// 'day', 'week', 'month' ou 'year'.
  final String unit;

  /// Repete a cada [interval] unidades.
  final int interval;

  /// Só na repetição semanal: dias da semana (1 = segunda … 7 = domingo).
  /// Vazio = o dia da semana em que o evento começa.
  final Set<int> weekdays;

  /// Último dia (inclusive) em que pode haver uma ocorrência.
  final DateTime? until;

  /// Número total de ocorrências.
  final int? count;

  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Há uma ocorrência a começar em [d], numa série iniciada em [first]?
  bool matches(DateTime first, DateTime d) {
    if (d.isBefore(first)) return false;
    if (until != null && d.isAfter(until!)) return false;
    final int index;
    switch (unit) {
      case 'day':
        final n = daysBetween(first, d);
        if (n % interval != 0) return false;
        index = n ~/ interval;
      case 'week':
        final days = (weekdays.isEmpty ? {first.weekday} : weekdays).toList()
          ..sort();
        if (!days.contains(d.weekday)) return false;
        final w = daysBetween(_monday(first), _monday(d)) ~/ 7;
        if (w % interval != 0) return false;
        // Dias da primeira semana anteriores ao início não contam.
        final skipped = days.where((x) => x < first.weekday).length;
        index =
            (w ~/ interval) * days.length + days.indexOf(d.weekday) - skipped;
      case 'month':
        if (d.day != first.day) return false;
        final m = (d.year - first.year) * 12 + d.month - first.month;
        if (m % interval != 0) return false;
        index = m ~/ interval;
      case 'year':
        if (d.month != first.month || d.day != first.day) return false;
        final y = d.year - first.year;
        if (y % interval != 0) return false;
        index = y ~/ interval;
      default:
        return false;
    }
    return count == null || index < count!;
  }

  /// A mesma regra com tudo deslocado [days] dias.
  Recurrence shifted(int days) => Recurrence(
    unit: unit,
    interval: interval,
    weekdays: {for (final w in weekdays) (w - 1 + days) % 7 + 1},
    until: until == null
        ? null
        : DateTime(until!.year, until!.month, until!.day + days),
    count: count,
  );

  factory Recurrence.fromJson(Map<String, dynamic> j) => Recurrence(
    unit: j['unit'] as String,
    interval: ((j['interval'] as num?)?.toInt() ?? 1).clamp(1, 999),
    weekdays: {
      for (final w in (j['weekdays'] as List? ?? [])) (w as num).toInt(),
    },
    until: j['until'] == null
        ? null
        : dateOnly(DateTime.parse(j['until'] as String)),
    count: (j['count'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'unit': unit,
    'interval': interval,
    if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (until != null) 'until': _ymd(until!),
    if (count != null) 'count': count,
  };
}

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
    this.recurrence,
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

  /// Repetição; `null` = evento único. [start] e [end] descrevem a primeira
  /// ocorrência.
  Recurrence? recurrence;

  /// Dias de calendário que cada ocorrência ocupa para além do primeiro.
  int get _extraDays {
    var last = dateOnly(end);
    // Um evento que acaba exatamente à meia-noite não ocupa o dia seguinte.
    if (!allDay && end == last && end.isAfter(start)) {
      last = last.subtract(const Duration(days: 1));
    }
    final n = daysBetween(start, last);
    return n < 0 ? 0 : n;
  }

  /// Cada ocorrência ocupa mais do que um dia?
  bool get multiDay => _extraDays > 0;

  /// Há uma ocorrência a começar no dia indicado?
  bool startsOn(DateTime day) {
    final d = dateOnly(day);
    final first = dateOnly(start);
    return recurrence == null ? d == first : recurrence!.matches(first, d);
  }

  /// O evento (ou uma das suas ocorrências) toca no dia indicado?
  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    for (var k = 0; k <= _extraDays; k++) {
      if (startsOn(DateTime(d.year, d.month, d.day - k))) return true;
    }
    return false;
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
      recurrence: j['recurrence'] == null
          ? null
          : Recurrence.fromJson(
              Map<String, dynamic>.from(j['recurrence'] as Map),
            ),
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
    'recurrence': recurrence?.toJson(),
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
    this.active = false,
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

  /// Marcada como "ativa": aparece no painel lateral do calendário.
  bool active;

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
      active: j['active'] as bool? ?? false,
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
    'active': active,
    'priority': priority,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
