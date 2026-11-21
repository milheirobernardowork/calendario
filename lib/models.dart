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

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Texto para comparar: minúsculas, sem acentos, espaços simples.
String normalizeText(String s) {
  final lower = s.toLowerCase().trim();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
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
    this.exdates = const {},
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

  /// Dias em que a ocorrência foi retirada da série (editada à parte,
  /// movida ou eliminada). Continuam a contar para [count].
  final Set<DateTime> exdates;

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
    if (count != null && index >= count!) return false;
    return !exdates.contains(d);
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
    exdates: {for (final d in exdates) DateTime(d.year, d.month, d.day + days)},
  );

  /// A mesma regra sem a ocorrência de [day].
  Recurrence excluding(DateTime day) => Recurrence(
    unit: unit,
    interval: interval,
    weekdays: weekdays,
    until: until,
    count: count,
    exdates: {...exdates, dateOnly(day)},
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
    exdates: {
      for (final d in (j['exdates'] as List? ?? []))
        dateOnly(DateTime.parse(d as String)),
    },
  );

  Map<String, dynamic> toJson() => {
    'unit': unit,
    'interval': interval,
    if (weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (until != null) 'until': _ymd(until!),
    if (count != null) 'count': count,
    if (exdates.isNotEmpty)
      'exdates': [for (final d in exdates.toList()..sort()) _ymd(d)],
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
    this.category,
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

  /// Coluna da página Eventos onde aparece (id de [EventColumn]); `null` =
  /// evento normal, só no calendário.
  String? category;

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

  /// Dia em que começa a ocorrência que toca em [day] (`null` se nenhuma).
  DateTime? occurrenceStartOn(DateTime day) {
    final d = dateOnly(day);
    for (var k = 0; k <= _extraDays; k++) {
      final s = DateTime(d.year, d.month, d.day - k);
      if (startsOn(s)) return s;
    }
    return null;
  }

  /// Próxima ocorrência a começar em [from] ou depois (até ~3 anos).
  DateTime? nextOccurrence(DateTime from) {
    final f = dateOnly(from);
    if (recurrence == null) {
      final s = dateOnly(start);
      return s.isBefore(f) ? null : s;
    }
    var d = dateOnly(start).isAfter(f) ? dateOnly(start) : f;
    for (var i = 0; i < 1100; i++, d = DateTime(d.year, d.month, d.day + 1)) {
      if (startsOn(d)) return d;
    }
    return null;
  }

  /// Cópia de uma só ocorrência, deslocada para começar em [day], como
  /// evento único com um id novo.
  Event occurrenceAt(DateTime day, {String? id}) {
    final offset = daysBetween(start, day);
    DateTime shift(DateTime t) =>
        DateTime(t.year, t.month, t.day + offset, t.hour, t.minute);
    return Event(
      id: id ?? newId(),
      title: title,
      notes: notes,
      start: shift(start),
      end: shift(end),
      allDay: allDay,
      color: color,
      category: category,
      updatedAt: DateTime.now().toUtc(),
    );
  }

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
      category: j['category'] as String?,
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
    'category': category,
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
    this.future = false,
    this.priority = 0,
    DateTime? createdAt,
    required super.updatedAt,
    super.deletedAt,
    super.dirty,
  }) : createdAt = createdAt ?? updatedAt;

  String title;
  String notes;

  /// Quando foi criada (ordena a secção "Por Fazer").
  final DateTime createdAt;

  /// Marcada como "futura": vai para a secção do fim da lista.
  bool future;

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
      future: j['future'] as bool? ?? false,
      createdAt: j['created_at'] == null
          ? null
          : DateTime.parse(j['created_at'] as String).toUtc(),
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
    'future': future,
    'created_at': createdAt.toIso8601String(),
    'priority': priority,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

/// Coluna da página Eventos (ex.: "Corridas").
class EventColumn extends Record {
  EventColumn({
    required super.id,
    required this.name,
    this.position = 0,
    required super.updatedAt,
    super.deletedAt,
    super.dirty,
  });

  /// Id fixo da coluna "Corridas", criada automaticamente: sendo igual em
  /// todos os dispositivos, nunca fica duplicada.
  static const corridasId = 'c0a1c0a1-0000-4000-8000-00000000c0a1';

  String name;

  /// Ordem das colunas (menor = mais à esquerda).
  int position;

  factory EventColumn.fromJson(Map<String, dynamic> j) => EventColumn(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    position: (j['position'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
    deletedAt: j['deleted_at'] == null
        ? null
        : DateTime.parse(j['deleted_at'] as String).toUtc(),
    dirty: j['dirty'] as bool? ?? false,
  );

  @override
  Map<String, dynamic> toRemote() => {
    'id': id,
    'name': name,
    'position': position,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

/// Página do Workspace: notas com títulos, texto, listas, tarefas, tabelas
/// e links, arrumadas em pastas (ex.: "ATEC", "IPS").
class WorkPage extends Record {
  WorkPage({
    required super.id,
    this.title = '',
    this.folder = '',
    this.color = 0,
    this.position = 0,
    List<Map<String, dynamic>>? blocks,
    required super.updatedAt,
    super.deletedAt,
    super.dirty,
  }) : blocks = blocks ?? [];

  String title;

  /// Nome da pasta ('' = sem pasta).
  String folder;

  /// Índice em `eventColors` (a bolinha ao lado do nome).
  int color;
  int position;

  /// Conteúdo: cada bloco é um mapa com `type` (h1, h2, text, bullet, todo,
  /// table, link) e os campos desse tipo (`text`, `checked`, `url`, `rows`).
  List<Map<String, dynamic>> blocks;

  factory WorkPage.fromJson(Map<String, dynamic> j) => WorkPage(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    folder: j['folder'] as String? ?? '',
    color: (j['color'] as num?)?.toInt() ?? 0,
    position: (j['position'] as num?)?.toInt() ?? 0,
    blocks: [
      for (final b in (j['blocks'] as List? ?? const []))
        Map<String, dynamic>.from(b as Map),
    ],
    updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
    deletedAt: j['deleted_at'] == null
        ? null
        : DateTime.parse(j['deleted_at'] as String).toUtc(),
    dirty: j['dirty'] as bool? ?? false,
  );

  @override
  Map<String, dynamic> toRemote() => {
    'id': id,
    'title': title,
    'folder': folder,
    'color': color,
    'position': position,
    'blocks': blocks,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
