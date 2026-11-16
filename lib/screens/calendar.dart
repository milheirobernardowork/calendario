// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../holidays.dart';
import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'event_edit.dart';
import 'tasks.dart';

/// O que é arrastado: o evento e o dia de onde foi agarrado.
typedef _Drag = ({Event event, DateTime day});

/// Troço de um evento de vários dias dentro de uma semana: colunas
/// [from]..[to] e a linha ([lane]) onde é desenhado.
typedef _Bar = ({Event event, int from, int to, int lane});

/// Disposição de uma semana: barras dos eventos de vários dias, linhas
/// reservadas para elas em cada dia, e os eventos de um só dia.
class _WeekLayout {
  _WeekLayout(this.days, this.bars, this.lanesOn, this.singles);

  final List<DateTime> days;
  final List<_Bar> bars;
  final List<int> lanesOn;
  final List<List<Event>> singles;

  /// Linhas ocupadas no dia mais cheio.
  int get rows =>
      [for (var i = 0; i < 7; i++) lanesOn[i] + singles[i].length]
          .reduce((a, b) => a > b ? a : b);
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.store,
    required this.selectedDay,
    required this.onDaySelected,
    this.onSwipeRight,
  });

  final Store store;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  /// Deslizar o dedo para a direita (no telemóvel).
  final VoidCallback? onSwipeRight;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  /// Um dia qualquer do período (mês ou semana) que está à vista.
  late DateTime _focused = widget.selectedDay;
  bool _weekView = false;

  final _gridScroll = ScrollController();

  // --- Teclado (desktop) ----------------------------------------------

  /// Evento debaixo do rato: é o que a tecla Del apaga.
  ({Event event, DateTime day})? _hovered;
  final _keysFocus = FocusNode(debugLabel: 'calendário');

  void _hover(Event e, DateTime day, bool on) {
    if (on) {
      _hovered = (event: e, day: day);
    } else if (_hovered?.event.id == e.id) {
      _hovered = null;
    }
  }

  /// Atalhos: N novo evento, T hoje, ← → mês anterior/seguinte, Del apagar
  /// o evento debaixo do rato. Só com o calendário à vista.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    void Function() when(void Function() f) => () {
      if (TickerMode.valuesOf(context).enabled) f();
    };
    return {
      const SingleActivator(LogicalKeyboardKey.keyN): when(
        () => openEventEditor(context, widget.store, day: widget.selectedDay),
      ),
      const SingleActivator(LogicalKeyboardKey.keyT): when(
        () => _select(dateOnly(DateTime.now())),
      ),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): when(
        () => _step(-1),
      ),
      const SingleActivator(LogicalKeyboardKey.arrowRight): when(
        () => _step(1),
      ),
      const SingleActivator(LogicalKeyboardKey.delete): when(() {
        final h = _hovered;
        if (h == null) return;
        _hovered = null;
        deleteWithUndo(context, widget.store, h.event, h.day);
      }),
    };
  }

  /// Teclas de atalho. Só quando o próprio calendário tem o teclado: se
  /// estiver a escrever-se num campo (ex.: nova tarefa), as letras são para
  /// esse campo.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (FocusManager.instance.primaryFocus != _keysFocus) {
      return KeyEventResult.ignored;
    }
    for (final entry in _shortcuts.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // --- Telemóvel: semanas seguidas, a começar na semana atual. ---------

  /// Ecrã estreito: calendário contínuo em vez de mês a mês.
  bool _continuous = false;

  /// Semana que aparece no topo ao abrir (ou depois de "Hoje" / escolher
  /// mês ou ano). As outras ficam acima e abaixo dela.
  late DateTime _anchorWeek = _monday(dateOnly(DateTime.now()));
  final _phoneScroll = ScrollController();
  Key _centerKey = UniqueKey();
  double _phoneWidth = 0;

  static final _firstWeek = _monday(DateTime(2000, 1, 3));
  static final _lastWeek = _monday(DateTime(2100, 12, 27));

  static const _monthLabelHeight = 34.0;

  /// A semana tem um dia 1? Então leva por cima o nome do mês.
  static bool _startsMonth(DateTime week) => [
    for (var i = 0; i < 7; i++) DateTime(week.year, week.month, week.day + i),
  ].any((d) => d.day == 1);

  double _phoneWeekHeight(DateTime week) {
    final rows = _layoutWeek(week).rows;
    final h = _cellChrome + rows * EventChipBox.extent;
    return (h < 56 ? 56.0 : h) + (_startsMonth(week) ? _monthLabelHeight : 0);
  }

  /// Semana no topo do ecrã, a partir da posição do scroll.
  DateTime _topWeek() {
    if (!_phoneScroll.hasClients) return _anchorWeek;
    var offset = _phoneScroll.offset;
    var week = _anchorWeek;
    if (offset >= 0) {
      while (week.isBefore(_lastWeek)) {
        final h = _phoneWeekHeight(week);
        if (offset < h) break;
        offset -= h;
        week = DateTime(week.year, week.month, week.day + 7);
      }
    } else {
      while (offset < 0 && week.isAfter(_firstWeek)) {
        week = DateTime(week.year, week.month, week.day - 7);
        offset += _phoneWeekHeight(week);
      }
    }
    return week;
  }

  void _onPhoneScroll() {
    // O mês/ano dos botões acompanha a semana que está no topo.
    final top = _topWeek();
    final mid = DateTime(top.year, top.month, top.day + 3);
    if (mid.month != _focused.month || mid.year != _focused.year) {
      setState(() => _focused = mid);
    }
  }

  /// Põe a semana de [day] no topo.
  void _anchorTo(DateTime day) => setState(() {
    _anchorWeek = _monday(dateOnly(day));
    _focused = day;
    _centerKey = UniqueKey();
    if (_phoneScroll.hasClients) _phoneScroll.jumpTo(0);
  });

  Widget _phoneHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
    child: Row(
      children: [
        _monthButton(context),
        _yearButton(context),
        const Spacer(),
        TextButton(
          onPressed: () => _anchorTo(dateOnly(DateTime.now())),
          child: const Text('Hoje'),
        ),
      ],
    ),
  );

  Widget _phoneWeekRow(BuildContext context, DateTime week, DateTime today) {
    final layout = _layoutWeek(week);
    final rows = layout.rows;
    final h = _cellChrome + rows * EventChipBox.extent;
    final row = _week(
      context,
      layout,
      h < 56 ? 56.0 : h,
      _phoneWidth,
      today,
      true,
    );
    if (!_startsMonth(week)) return row;
    final first = layout.days.firstWhere((d) => d.day == 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _monthLabelHeight,
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            fmtMonth(first),
            style: Theme.of(context).textTheme.titleMedium!
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        row,
      ],
    );
  }

  Widget _phone(BuildContext context, double width) {
    _phoneWidth = width;
    final today = dateOnly(DateTime.now());
    final past = daysBetween(_firstWeek, _anchorWeek) ~/ 7;
    final future = daysBetween(_anchorWeek, _lastWeek) ~/ 7 + 1;
    return GestureDetector(
      // Deslizar para a direita abre as tarefas.
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) widget.onSwipeRight?.call();
      },
      child: Column(
        children: [
          _phoneHeader(context),
          _weekdays(context),
          Expanded(
            child: CustomScrollView(
              controller: _phoneScroll,
              center: _centerKey,
              slivers: [
                SliverList.builder(
                  itemCount: past,
                  itemBuilder: (context, i) => _phoneWeekRow(
                    context,
                    DateTime(
                      _anchorWeek.year,
                      _anchorWeek.month,
                      _anchorWeek.day - 7 * (i + 1),
                    ),
                    today,
                  ),
                ),
                SliverList.builder(
                  key: _centerKey,
                  itemCount: future,
                  itemBuilder: (context, i) => _phoneWeekRow(
                    context,
                    DateTime(
                      _anchorWeek.year,
                      _anchorWeek.month,
                      _anchorWeek.day + 7 * i,
                    ),
                    today,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime _lastWheel = DateTime(0);

  @override
  void initState() {
    super.initState();
    _phoneScroll.addListener(_onPhoneScroll);
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    _phoneScroll.dispose();
    _keysFocus.dispose();
    super.dispose();
  }

  /// Roda do rato: muda de mês (ou semana). Se a grelha não couber no ecrã,
  /// primeiro rola até ao fim e só depois muda.
  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
    final forward = e.scrollDelta.dy > 0;
    if (_gridScroll.hasClients) {
      final p = _gridScroll.position;
      final canScroll = forward
          ? p.pixels < p.maxScrollExtent - 1
          : p.pixels > p.minScrollExtent + 1;
      if (canScroll) return;
    }
    // Um passo de cada vez, mesmo que a roda envie vários eventos seguidos.
    final now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 200)) return;
    _lastWheel = now;
    _step(forward ? 1 : -1);
  }

  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Primeiro dia (segunda-feira) de cada semana à vista.
  List<DateTime> get _weeks {
    if (_weekView) return [_monday(_focused)];
    final last = DateTime(_focused.year, _focused.month + 1, 0);
    final weeks = <DateTime>[];
    for (
      var w = _monday(DateTime(_focused.year, _focused.month));
      !w.isAfter(last);
      w = DateTime(w.year, w.month, w.day + 7)
    ) {
      weeks.add(w);
    }
    return weeks;
  }

  String get _title {
    if (!_weekView) return fmtMonth(_focused);
    final first = _monday(_focused);
    final last = DateTime(first.year, first.month, first.day + 6);
    return '${fmtDateShort(first)} – ${fmtDateShort(last)} ${last.year}';
  }

  void _step(int dir) => setState(() {
    _focused = _weekView
        ? DateTime(_focused.year, _focused.month, _focused.day + 7 * dir)
        : DateTime(_focused.year, _focused.month + dir);
  });

  void _select(DateTime day) {
    if (_continuous) {
      widget.onDaySelected(dateOnly(day));
      return;
    }
    setState(() => _focused = day);
    widget.onDaySelected(dateOnly(day));
  }

  Future<void> _dropped(_Drag drag, DateTime target) async {
    final days = daysBetween(drag.day, target);
    if (days == 0) return;
    final copy = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${drag.event.title}"'),
        content: Text(
          drag.event.recurrence == null
              ? 'Mover ou copiar para ${fmtDayLong(target)}?'
              : 'Este evento repete-se. Só a ocorrência de '
                    '${fmtDateShort(drag.day)} é movida ou copiada para '
                    '${fmtDayLong(target)}; o resto da série fica igual.',
          style: const TextStyle(fontSize: 17),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            style: bigButton,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            style: bigButton,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copiar'),
          ),
          FilledButton(
            style: bigButton,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mover'),
          ),
        ],
      ),
    );
    if (copy == null) return;
    widget.store.shiftEvent(drag.event, days, copy: copy, from: drag.day);
  }

  /// Vai para o mês [month] do ano [year] (dia 1).
  void _jumpTo(int year, int month) => _continuous
      ? _anchorTo(DateTime(year, month))
      : setState(() => _focused = DateTime(year, month));

  static const _monthNames = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  Widget _monthButton(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Escolher o mês',
      initialValue: _focused.month,
      onSelected: (m) => _jumpTo(_focused.year, m),
      itemBuilder: (context) => [
        for (var m = 1; m <= 12; m++)
          PopupMenuItem(value: m, height: 40, child: Text(_monthNames[m - 1])),
      ],
      child: _dropLabel(context, _monthNames[_focused.month - 1]),
    );
  }

  Widget _yearButton(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final year = await showDialog<int>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Escolher o ano'),
            contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
            content: SizedBox(
              width: 320,
              height: 360,
              child: YearPicker(
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                selectedDate: _focused,
                onChanged: (d) => Navigator.pop(dialog, d.year),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
        if (year != null) _jumpTo(year, _focused.month);
      },
      child: Tooltip(
        message: 'Escolher o ano',
        child: _dropLabel(context, '${_focused.year}'),
      ),
    );
  }

  /// Texto com uma seta para baixo, como uma lista de escolha.
  Widget _dropLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    ),
  );

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _step(-1),
          ),
          IconButton(
            tooltip: 'Seguinte',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _step(1),
          ),
          const SizedBox(width: 4),
          Expanded(
            // Em ecrãs estreitos os botões de mês e ano já dizem onde se está.
            child: MediaQuery.sizeOf(context).width < 600
                ? const SizedBox.shrink()
                : Text(
                    _title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
          ),
          TextButton(
            onPressed: () => _select(dateOnly(DateTime.now())),
            child: const Text('Hoje'),
          ),
          _monthButton(context),
          _yearButton(context),
          IconButton(
            tooltip: _weekView ? 'Ver mês' : 'Ver semana',
            icon: Icon(
              _weekView ? Icons.calendar_view_month : Icons.calendar_view_week,
            ),
            onPressed: () => setState(() => _weekView = !_weekView),
          ),
        ],
      ),
    );
  }

  Widget _weekdays(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium!
        .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final monday = _monday(_focused);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(
                fmtWeekday(DateTime(monday.year, monday.month, monday.day + i)),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
        ],
      ),
    );
  }

  /// Grelha de semanas. Cada semana tem pelo menos [minRowHeight] e cresce
  /// até caber o dia com mais eventos. Com [fill], as semanas repartem essa
  /// altura: as mais vazias encolhem para dar espaço às mais cheias, e só se
  /// nem assim couber é que a grelha passa a rolar.
  Widget _grid(
    BuildContext context,
    double width, {
    double minRowHeight = 0,
    double? fill,
  }) {
    final today = dateOnly(DateTime.now());
    final compact = width / 7 < 90;
    final weeks = _weeks;
    final layouts = {for (final w in weeks) w: _layoutWeek(w)};
    final needed = <DateTime, double>{};
    for (final week in weeks) {
      final h = _cellChrome + layouts[week]!.rows * EventChipBox.extent;
      needed[week] = h > minRowHeight ? h : minRowHeight;
    }
    var share = 0.0;
    if (fill != null) {
      // Altura comum das semanas que não precisam de mais do que isso.
      share = fill / weeks.length;
      for (var pass = 0; pass < weeks.length; pass++) {
        final big = needed.values.where((h) => h > share);
        final rest = weeks.length - big.length;
        if (rest == 0) break;
        final next = (fill - big.fold(0.0, (a, h) => a + h)) / rest;
        if (next >= share) break;
        share = next;
      }
    }
    final heights = {
      for (final w in weeks) w: needed[w]! > share ? needed[w]! : share,
    };
    final total = needed.values.fold(0.0, (a, h) => a + h);
    if (fill != null && total > fill) {
      // Nem assim cabe: encolher as semanas que já passaram, mantendo a
      // atual e as seguintes completas. Os eventos escondidos ficam "+N".
      final thisWeek = _monday(today);
      final past = weeks.where((w) => w.isBefore(thisWeek)).toList();
      const floor = _cellChrome + EventChipBox.extent;
      double pastTotal(double cap) =>
          past.fold(0.0, (a, w) => a + (needed[w]! < cap ? needed[w]! : cap));
      final target = pastTotal(double.infinity) - (total - fill);
      var lo = floor, hi = fill;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        pastTotal(mid) > target ? hi = mid : lo = mid;
      }
      for (final w in past) {
        if (needed[w]! > lo) heights[w] = lo;
      }
    }
    double height(DateTime week) => heights[week]!;

    return Column(
      children: [
        for (final week in weeks)
          _week(context, layouts[week]!, height(week), width, today, compact),
      ],
    );
  }

  /// Distribui os eventos de vários dias por linhas, como barras contínuas.
  _WeekLayout _layoutWeek(DateTime week) {
    final days = [
      for (var i = 0; i < 7; i++) DateTime(week.year, week.month, week.day + i),
    ];
    final perDay = [for (final d in days) widget.store.eventsOn(d)];
    final segments = <({Event event, int from, int to})>[];
    for (var i = 0; i < 7; i++) {
      for (final e in perDay[i]) {
        if (!e.multiDay) continue;
        if (i > 0 && perDay[i - 1].contains(e)) continue; // já começou antes
        var j = i;
        while (j < 6 && perDay[j + 1].contains(e)) {
          j++;
        }
        segments.add((event: e, from: i, to: j));
      }
    }
    // Primeiro os que começam mais cedo; no mesmo dia, os mais longos.
    segments.sort(
      (a, b) => a.from != b.from
          ? a.from - b.from
          : (b.to - b.from) - (a.to - a.from),
    );
    final laneEnds = <int>[];
    final bars = <_Bar>[];
    for (final s in segments) {
      var lane = laneEnds.indexWhere((end) => end < s.from);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(s.to);
      } else {
        laneEnds[lane] = s.to;
      }
      bars.add((event: s.event, from: s.from, to: s.to, lane: lane));
    }
    final lanesOn = List.filled(7, 0);
    for (final b in bars) {
      for (var i = b.from; i <= b.to; i++) {
        if (b.lane + 1 > lanesOn[i]) lanesOn[i] = b.lane + 1;
      }
    }
    final singles = [
      for (final list in perDay)
        [
          for (final e in list)
            if (!e.multiDay) e,
        ],
    ];
    return _WeekLayout(days, bars, lanesOn, singles);
  }

  /// Distância do topo da célula à primeira linha de eventos: borda +
  /// margem + número do dia + espaço.
  static const _firstRowTop = 0.5 + 3 + 24 + 2;

  Widget _week(
    BuildContext context,
    _WeekLayout layout,
    double height,
    double width,
    DateTime today,
    bool compact,
  ) {
    // Quantas linhas de eventos cabem na altura desta semana.
    final room = ((height - _cellChrome + 0.5) / EventChipBox.extent).floor();
    final cw = width / 7;
    final hiddenBars = List.filled(7, 0);
    for (final b in layout.bars) {
      if (b.lane < room) continue;
      for (var i = b.from; i <= b.to; i++) {
        hiddenBars[i]++;
      }
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _cell(
                      context,
                      layout.days[i],
                      today,
                      compact,
                      room,
                      layout.lanesOn[i],
                      layout.singles[i],
                      hiddenBars[i],
                    ),
                  ),
              ],
            ),
          ),
          for (final b in layout.bars)
            if (b.lane < room)
              Positioned(
                left: b.from * cw,
                width: (b.to - b.from + 1) * cw - 0.5,
                top: _firstRowTop + b.lane * EventChipBox.extent,
                height: EventChipBox.extent,
                child: _EventChip(
                  store: widget.store,
                  event: b.event,
                  day: layout.days[b.from],
                  compact: compact && b.from == b.to,
                  onHover: (on) => _hover(b.event, layout.days[b.from], on),
                  onTap: () => _continuous
                      ? _showDay(layout.days[b.from])
                      : openEventEditor(
                          context,
                          widget.store,
                          event: b.event,
                          day: layout.days[b.from],
                        ),
                ),
              ),
        ],
      ),
    );
  }

  /// Altura de uma célula sem eventos: margens + número do dia.
  static const _cellChrome = 3.0 + 24 + 2 + 4;

  Widget _cell(
    BuildContext context,
    DateTime day,
    DateTime today,
    bool compact,
    int room,
    int lanes,
    List<Event> singles,
    int hiddenBars,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // As primeiras [lanes] linhas ficam para as barras de vários dias.
    final reserved = lanes < room ? lanes : room;
    final free = room - reserved;
    // Se não couberem todos, a última linha passa a "+N".
    final fits = singles.length <= free && hiddenBars == 0;
    final shown = fits ? singles.length : (free - 1).clamp(0, singles.length);
    final hidden = singles.length - shown + hiddenBars;
    final selected = day == widget.selectedDay;
    final isToday = day == today;
    final outside = !_continuous && !_weekView && day.month != _focused.month;

    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => d.data.day != day,
      onAcceptWithDetails: (d) => _dropped(d.data, day),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Espaço em branco: seleciona o dia e começa um evento novo nele.
          onTap: () async {
            // No telemóvel, tocar num dia mostra os eventos desse dia.
            if (_continuous) {
              _showDay(day);
              return;
            }
            // O editor abre primeiro; o dia só fica selecionado depois, para
            // não redesenhar o calendário inteiro no mesmo instante.
            await openEventEditor(context, widget.store, day: day);
            if (mounted) _select(day);
          },
          child: Container(
            decoration: BoxDecoration(
              color: hovering
                  ? scheme.primary.withValues(alpha: 0.18)
                  : selected
                  ? scheme.primary.withValues(alpha: 0.07)
                  : null,
              border: Border(
                top: BorderSide(color: scheme.outlineVariant, width: 0.5),
                right: BorderSide(color: scheme.outlineVariant, width: 0.5),
              ),
            ),
            padding: const EdgeInsets.only(top: 3, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  // O número só seleciona o dia (atualiza o painel lateral).
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _select(day),
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? scheme.primary : null,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected || isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isToday
                              ? scheme.onPrimary
                              : outside
                              ? scheme.outline
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(height: reserved * EventChipBox.extent),
                for (final e in singles.take(shown))
                  _EventChip(
                    store: widget.store,
                    event: e,
                    day: day,
                    compact: compact,
                    faded: outside,
                    onHover: (on) => _hover(e, day, on),
                    onTap: () => _continuous
                        ? _showDay(day)
                        : openEventEditor(
                            context,
                            widget.store,
                            event: e,
                            day: day,
                          ),
                  ),
                if (hidden > 0 && free > 0)
                  SizedBox(
                    height: EventChipBox.extent,
                    child: Center(
                      child: Tooltip(
                        message: 'Ver os eventos deste dia',
                        child: Material(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _showDay(day),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              child: Text(
                                '+$hidden',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pop-up com todos os eventos de um dia (para os dias encolhidos).
  Future<void> _showDay(DateTime day) {
    _select(day);
    return showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(fmtDayLong(day)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: 380,
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => ListView(
              shrinkWrap: true,
              children: [
                if (widget.store.eventsOn(day).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Sem eventos neste dia',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                for (final e in widget.store.eventsOn(day))
                  _EventTile(
                    event: e,
                    day: day,
                    store: widget.store,
                    onOpen: () => Navigator.pop(dialog),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialog);
              openEventEditor(context, widget.store, day: day);
            },
            icon: const Icon(Icons.add),
            label: const Text('Novo evento'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge!
          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  /// Tarefas marcadas como ativas e tarefas com data no dia selecionado.
  List<Widget> _dayTasks(BuildContext context) {
    final day = widget.selectedDay;
    final today = dateOnly(DateTime.now());
    final tasks = widget.store.tasks
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        if (a.priority != b.priority) return b.priority - a.priority;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final active = tasks.where((t) => t.active && !t.done).toList();
    // As ativas já estão na lista de cima; não repetir.
    final forDay = tasks
        .where((t) => t.due == day && !(t.active && !t.done))
        .toList();
    Widget tile(Task t) =>
        TaskTile(task: t, store: widget.store, today: today, compact: true);
    return [
      _section(context, 'Tarefas ativas'),
      ...active.map(tile),
      QuickAddTask(
        hint: 'Nova tarefa ativa…',
        onAdd: (title) => widget.store.saveTask(
          Task(
            id: newId(),
            title: title,
            active: true,
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
      ),
      _section(context, 'Tarefas deste dia'),
      ...forDay.map(tile),
      QuickAddTask(
        hint: 'Nova tarefa para ${fmtDateShort(day)}…',
        onAdd: (title) => widget.store.saveTask(
          Task(
            id: newId(),
            title: title,
            due: day,
            updatedAt: DateTime.now().toUtc(),
          ),
        ),
      ),
    ];
  }

  Widget _dayHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Text(
      fmtDayLong(widget.selectedDay),
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );

  List<Widget> _dayEvents(BuildContext context) {
    final events = widget.store.eventsOn(widget.selectedDay);
    if (events.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Sem eventos neste dia',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ];
    }
    return [
      for (final e in events)
        _EventTile(event: e, day: widget.selectedDay, store: widget.store),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    return StoreListener(
      listenable: widget.store,
      builder: (context) => Listener(
        onPointerSignal: _onWheel,
        child: LayoutBuilder(
          builder: (context, box) {
            _continuous = box.maxWidth < 600;
            if (_continuous) return _phone(context, box.maxWidth);
            if (box.maxWidth >= 840) {
              return Focus(
                focusNode: _keysFocus,
                autofocus: true,
                onKeyEvent: _onKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      // Clicar no calendário (não no painel das tarefas)
                      // devolve-lhe o teclado, tirando-o a um campo de texto
                      // onde se estivesse a escrever.
                      child: Listener(
                        onPointerDown: (_) {
                          if (!_keysFocus.hasPrimaryFocus) {
                            _keysFocus.requestFocus();
                          }
                        },
                        child: Column(
                          children: [
                            _header(context),
                            _weekdays(context),
                            Expanded(
                              // As semanas enchem a altura disponível e, se
                              // houver muitos eventos, crescem e a grelha
                              // passa a rolar.
                              child: LayoutBuilder(
                                builder: (context, area) =>
                                    SingleChildScrollView(
                                      controller: _gridScroll,
                                      child: _grid(
                                        context,
                                        area.maxWidth,
                                        fill: area.maxHeight,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, color: divider),
                    SizedBox(
                      width: 250,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [_dayHeader(context), ..._dayTasks(context)],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                _header(context),
                _weekdays(context),
                Expanded(
                  child: ListView(
                    controller: _gridScroll,
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      _grid(context, box.maxWidth, minRowHeight: 56),
                      Divider(height: 1, color: divider),
                      _dayHeader(context),
                      ..._dayEvents(context),
                      ..._dayTasks(context),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Evento dentro da célula de um dia; pode ser arrastado para outro dia.
class _EventChip extends StatelessWidget {
  const _EventChip({
    required this.event,
    required this.day,
    required this.onTap,
    required this.compact,
    required this.store,
    this.faded = false,
    this.onHover,
  });

  final bool compact;
  final Store store;

  /// O rato entrou (`true`) ou saiu (`false`) do evento.
  final ValueChanged<bool>? onHover;

  final Event event;
  final DateTime day;
  final VoidCallback onTap;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final chip = EventChipBox(event: event, day: day, compact: compact);
    final child = GestureDetector(
      // Os feriados são calculados: não se editam nem se apagam.
      onTap: event.isHoliday ? null : onTap,
      onSecondaryTapDown: event.isHoliday
          ? null
          : (d) => showEventMenu(context, store, event, day, d.globalPosition),
      child: Opacity(opacity: faded ? 0.55 : 1, child: chip),
    );
    if (event.isHoliday) return child;
    // Ao passar o rato: as notas (só se houver) e "selecionado" para o Del.
    final notes = event.notes.trim();
    final hoverable = MouseRegion(
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: notes.isEmpty
          ? child
          : Tooltip(
              message: notes,
              waitDuration: const Duration(milliseconds: 400),
              child: child,
            ),
    );
    final feedback = Material(
      color: Colors.transparent,
      elevation: 4,
      child: SizedBox(
        width: 170,
        child: EventChipBox(event: event, day: day, compact: false),
      ),
    );
    final _Drag data = (event: event, day: day);
    // Em ecrãs táteis o arrasto começa com toque longo, para não interferir
    // com o deslizar da página.
    final touch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return touch
        ? LongPressDraggable<_Drag>(
            data: data,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: child,
          )
        : Draggable<_Drag>(
            data: data,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: hoverable,
          );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.day,
    required this.store,
    this.onOpen,
  });

  final Event event;

  /// Dia em que aparece (numa série, a ocorrência que se abre).
  final DateTime day;
  final Store store;

  /// Chamado antes de abrir o editor (ex.: fechar o pop-up onde está).
  final VoidCallback? onOpen;

  String get _when {
    final e = event;
    final multiDay = dateOnly(e.start) != dateOnly(e.end);
    if (e.recurrence != null && !multiDay) {
      return e.allDay
          ? 'Dia inteiro · repete'
          : '${fmtTime(e.start)} – ${fmtTime(e.end)} · repete';
    }
    if (e.allDay) {
      return multiDay
          ? 'Dia inteiro · ${fmtDateShort(e.start)} – ${fmtDateShort(e.end)}'
          : 'Dia inteiro';
    }
    if (!multiDay) return '${fmtTime(e.start)} – ${fmtTime(e.end)}';
    return '${fmtDateShort(e.start)} ${fmtTime(e.start)} – '
        '${fmtDateShort(e.end)} ${fmtTime(e.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Container(
        width: 6,
        height: 40,
        decoration: BoxDecoration(
          color: eventColor(event.color),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(event.isHoliday ? 'Feriado' : _when),
      onTap: event.isHoliday
          ? null
          : () {
              onOpen?.call();
              openEventEditor(context, store, event: event, day: day);
            },
    );
    if (event.isHoliday) return tile;
    return GestureDetector(
      onSecondaryTapDown: (d) =>
          showEventMenu(context, store, event, day, d.globalPosition),
      child: tile,
    );
  }
}

/// Menu do botão direito sobre um evento: editar ou eliminar. Num evento
/// repetido, eliminar pode ser só desse dia ou da série inteira. Depois de
/// eliminar, aparece "Anular" durante uns segundos.
Future<void> showEventMenu(
  BuildContext context,
  Store store,
  Event event,
  DateTime day,
  Offset position,
) async {
  final series = event.recurrence != null;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        enabled: false,
        child: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      const PopupMenuItem(
        value: 'edit',
        child: ListTile(
          leading: Icon(Icons.edit_outlined),
          title: Text('Editar'),
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(series ? 'Eliminar só este dia' : 'Eliminar'),
        ),
      ),
      if (series)
        PopupMenuItem(
          value: 'delete-series',
          child: ListTile(
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Eliminar a série'),
          ),
        ),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'edit') {
    await openEventEditor(context, store, event: event, day: day);
    return;
  }
  deleteWithUndo(
    context,
    store,
    event,
    day,
    wholeSeries: choice == 'delete-series',
  );
}

/// Apaga um evento (numa série, por omissão só o dia [day]) e mostra
/// "Anular" durante uns segundos.
void deleteWithUndo(
  BuildContext context,
  Store store,
  Event event,
  DateTime day, {
  bool wholeSeries = false,
}) {
  final before = event.recurrence;
  final occurrence = event.occurrenceStartOn(day) ?? dateOnly(day);
  if (event.recurrence != null && !wholeSeries) {
    store.excludeOccurrence(event, occurrence);
  } else {
    store.deleteEvent(event);
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('"${event.title}" eliminado'),
      action: SnackBarAction(
        label: 'Anular',
        onPressed: () => store.restoreEvent(event, recurrence: before),
      ),
    ),
  );
}
