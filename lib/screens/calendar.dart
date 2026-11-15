// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'event_edit.dart';
import 'tasks.dart';

/// O que é arrastado: o evento e o dia de onde foi agarrado.
typedef _Drag = ({Event event, DateTime day});

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.store,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final Store store;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  /// Um dia qualquer do período (mês ou semana) que está à vista.
  late DateTime _focused = widget.selectedDay;
  bool _weekView = false;

  final _gridScroll = ScrollController();
  DateTime _lastWheel = DateTime(0);

  @override
  void dispose() {
    _gridScroll.dispose();
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
    if (now.difference(_lastWheel) < const Duration(milliseconds: 300)) return;
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
              : 'Este evento repete-se. "Mover" desloca todas as '
                    'ocorrências; "Copiar" cria um evento único em '
                    '${fmtDayLong(target)}.',
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
            child: Text(
              _title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: () => _select(dateOnly(DateTime.now())),
            child: const Text('Hoje'),
          ),
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
    final needed = <DateTime, double>{};
    for (final week in weeks) {
      var most = 0;
      for (var i = 0; i < 7; i++) {
        final n = widget.store
            .eventsOn(DateTime(week.year, week.month, week.day + i))
            .length;
        if (n > most) most = n;
      }
      final h = _cellChrome + most * EventChipBox.extent;
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
          SizedBox(
            height: height(week),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _cell(
                      context,
                      DateTime(week.year, week.month, week.day + i),
                      today,
                      compact,
                      // Quantos blocos cabem na altura desta semana.
                      ((height(week) - _cellChrome + 0.5) / EventChipBox.extent)
                          .floor(),
                    ),
                  ),
              ],
            ),
          ),
      ],
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
  ) {
    final scheme = Theme.of(context).colorScheme;
    final events = widget.store.eventsOn(day);
    // Se não couberem todos, a última linha passa a "+N".
    final shown = events.length <= room
        ? events.length
        : (room - 1).clamp(0, events.length);
    final hidden = events.length - shown;
    final selected = day == widget.selectedDay;
    final isToday = day == today;
    final outside = !_weekView && day.month != _focused.month;

    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => d.data.day != day,
      onAcceptWithDetails: (d) => _dropped(d.data, day),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Espaço em branco: seleciona o dia e começa um evento novo nele.
          onTap: () {
            _select(day);
            openEventEditor(context, widget.store, day: day);
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
                for (final e in events.take(shown))
                  _EventChip(
                    event: e,
                    day: day,
                    compact: compact,
                    faded: outside,
                    onTap: () => openEventEditor(
                      context,
                      widget.store,
                      event: e,
                      day: day,
                    ),
                  ),
                if (hidden > 0 && room > 0)
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
                for (final e in widget.store.eventsOn(day))
                  _EventTile(
                    event: e,
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

  Widget _empty(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
      if (active.isEmpty) _empty(context, 'Nenhuma tarefa ativa'),
      ...active.map(tile),
      _section(context, 'Tarefas deste dia'),
      if (forDay.isEmpty) _empty(context, 'Nenhuma tarefa para este dia'),
      ...forDay.map(tile),
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
    return [for (final e in events) _EventTile(event: e, store: widget.store)];
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Listener(
        onPointerSignal: _onWheel,
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 840) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _header(context),
                        _weekdays(context),
                        Expanded(
                          // As semanas enchem a altura disponível e, se houver
                          // muitos eventos, crescem e a grelha passa a rolar.
                          child: LayoutBuilder(
                            builder: (context, area) => SingleChildScrollView(
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
                  VerticalDivider(width: 1, color: divider),
                  SizedBox(
                    width: 250,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [_dayHeader(context), ..._dayTasks(context)],
                    ),
                  ),
                ],
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
    this.faded = false,
  });

  final bool compact;

  final Event event;
  final DateTime day;
  final VoidCallback onTap;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final chip = EventChipBox(event: event, day: day, compact: compact);
    final child = GestureDetector(
      onTap: onTap,
      child: Opacity(opacity: faded ? 0.55 : 1, child: chip),
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
            child: child,
          );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.store, this.onOpen});

  final Event event;
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
    return ListTile(
      leading: Container(
        width: 6,
        height: 40,
        decoration: BoxDecoration(
          color: eventColor(event.color),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_when),
      onTap: () {
        onOpen?.call();
        openEventEditor(context, store, event: event);
      },
    );
  }
}
