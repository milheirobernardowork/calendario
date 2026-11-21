import 'models.dart';

/// Prefixo do id dos feriados (eventos calculados, nunca gravados).
const holidayPrefix = 'feriado:';

/// Cor dos feriados: lilás (índice em `eventColors`).
const holidayColor = 9;

extension HolidayEvent on Event {
  bool get isHoliday => id.startsWith(holidayPrefix);
}

/// Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher, calendário
/// gregoriano).
DateTime easter(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

/// Feriados nacionais de Portugal (e o Carnaval, habitualmente
/// tolerância de ponto) de um ano.
Map<DateTime, String> portugueseHolidays(int year) {
  final p = easter(year);
  DateTime fromEaster(int days) => DateTime(p.year, p.month, p.day + days);
  return {
    DateTime(year, 1, 1): 'Dia de Ano Novo',
    fromEaster(-47): 'Carnaval',
    fromEaster(-2): 'Sexta-feira Santa',
    p: 'Páscoa',
    DateTime(year, 4, 25): 'Dia da Liberdade',
    DateTime(year, 5, 1): 'Dia do Trabalhador',
    fromEaster(60): 'Corpo de Deus',
    DateTime(year, 6, 10): 'Dia de Portugal',
    DateTime(year, 8, 15): 'Assunção de Nossa Senhora',
    DateTime(year, 10, 5): 'Implantação da República',
    DateTime(year, 11, 1): 'Dia de Todos os Santos',
    DateTime(year, 12, 1): 'Dia da Restauração da Independência',
    DateTime(year, 12, 8): 'Imaculada Conceição',
    DateTime(year, 12, 25): 'Dia de Natal',
  };
}

final _cache = <int, Map<DateTime, Event>>{};

/// Feriado num dia, como evento de dia inteiro (ou `null`).
Event? holidayOn(DateTime day) {
  final d = dateOnly(day);
  final year = _cache[d.year] ??= {
    for (final h in portugueseHolidays(d.year).entries)
      h.key: Event(
        id: '$holidayPrefix${h.key.toIso8601String().substring(0, 10)}',
        title: h.value,
        start: h.key,
        end: h.key,
        allDay: true,
        color: holidayColor,
        updatedAt: DateTime.utc(2000),
      ),
  };
  return year[d];
}
