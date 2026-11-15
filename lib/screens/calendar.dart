// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'event_edit.dart';

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
        content: Text('Mover ou copiar para ${fmtDayLong(target)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mover'),
          ),
        ],
      ),
    );
    if (copy == null) return;
    widget.store.shiftEvent(drag.event, days, copy: copy);
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

  /// Grelha de semanas. Cada semana cresce até caber o dia com mais eventos;
  /// [minRowHeight] é a altura mínima de cada uma.
  Widget _grid(BuildContext context, double minRowHeight, double width) {
    final today = dateOnly(DateTime.now());
    final compact = width / 7 < 90;
    double height(DateTime week) {
      var most = 0;
      for (var i = 0; i < 7; i++) {
        final n = widget.store
            .eventsOn(DateTime(week.year, week.month, week.day + i))
            .length;
        if (n > most) most = n;
      }
      final needed = _cellChrome + most * _EventChip.extent;
      return needed > minRowHeight ? needed : minRowHeight;
    }

    return Column(
      children: [
        for (final week in _weeks)
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
  ) {
    final scheme = Theme.of(context).colorScheme;
    final events = widget.store.eventsOn(day);
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
          onTap: () => _select(day),
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
                const SizedBox(height: 2),
                for (final e in events)
                  _EventChip(
                    event: e,
                    day: day,
                    compact: compact,
                    faded: outside,
                    onTap: () =>
                        openEventEditor(context, widget.store, event: e),
                  ),
              ],
            ),
          ),
        );
      },
    );
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
      builder: (context, _) => LayoutBuilder(
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
                            child: _grid(
                              context,
                              area.maxHeight / _weeks.length,
                              area.maxWidth,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 1, color: divider),
                SizedBox(
                  width: 320,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [_dayHeader(context), ..._dayEvents(context)],
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
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    _grid(context, 56, box.maxWidth),
                    Divider(height: 1, color: divider),
                    _dayHeader(context),
                    ..._dayEvents(context),
                  ],
                ),
              ),
            ],
          );
        },
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

  /// Altura ocupada por cada evento na célula (20 + margens).
  static const extent = 22.0;
  final bool compact;

  final Event event;
  final DateTime day;
  final VoidCallback onTap;
  final bool faded;

  Widget _chip(BuildContext context, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final color = eventColor(event.color);
    // Dia inteiro: bloco cheio. Com hora: fundo suave e barra de cor.
    final solid = event.allDay;
    final showTime = !compact && !event.allDay && dateOnly(event.start) == day;
    return Container(
      height: 20,
      margin: const EdgeInsets.fromLTRB(2, 1, 2, 1),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: solid ? null : Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(
        showTime ? '${fmtTime(event.start)} ${event.title}' : event.title,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          height: 1.1,
          color: solid ? Colors.white : scheme.onSurface,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chip = _chip(context, compact: compact);
    final child = GestureDetector(
      onTap: onTap,
      child: Opacity(opacity: faded ? 0.55 : 1, child: chip),
    );
    final feedback = Material(
      color: Colors.transparent,
      elevation: 4,
      child: SizedBox(width: 170, child: _chip(context, compact: false)),
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
  const _EventTile({required this.event, required this.store});

  final Event event;
  final Store store;

  String get _when {
    final e = event;
    final multiDay = dateOnly(e.start) != dateOnly(e.end);
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
      onTap: () => openEventEditor(context, store, event: event),
    );
  }
}
