// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'event_edit.dart';

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
  late DateTime _focused = widget.selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  void _select(DateTime day) {
    setState(() => _focused = day);
    widget.onDaySelected(dateOnly(day));
  }

  Widget _calendar(BuildContext context, {required bool fill}) {
    final scheme = Theme.of(context).colorScheme;
    return TableCalendar<Event>(
      locale: locale,
      firstDay: DateTime(2000),
      lastDay: DateTime(2100, 12, 31),
      focusedDay: _focused,
      calendarFormat: _format,
      shouldFillViewport: fill,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Mês',
        CalendarFormat.twoWeeks: '2 semanas',
        CalendarFormat.week: 'Semana',
      },
      selectedDayPredicate: (d) => isSameDay(d, widget.selectedDay),
      eventLoader: widget.store.eventsOn,
      onDaySelected: (selected, _) => _select(selected),
      onPageChanged: (focused) => _focused = focused,
      onFormatChanged: (f) => setState(() => _format = f),
      headerStyle: HeaderStyle(
        formatButtonShowsNext: false,
        titleCentered: true,
        titleTextStyle: Theme.of(context).textTheme.titleMedium!,
      ),
      daysOfWeekHeight: 28,
      daysOfWeekStyle: DaysOfWeekStyle(
        dowTextFormatter: (d, l) =>
            DateFormat.E(l).format(d).substring(0, 3).toLowerCase(),
      ),
      calendarStyle: CalendarStyle(
        weekendTextStyle: TextStyle(color: scheme.onSurfaceVariant),
        outsideTextStyle: TextStyle(color: scheme.outlineVariant),
      ),
      calendarBuilders: CalendarBuilders(
        // Círculos de tamanho fixo, para não crescerem com a janela.
        selectedBuilder: (context, day, _) => _DayCircle(
          day: day,
          fill: scheme.primary,
          textColor: scheme.onPrimary,
        ),
        todayBuilder: (context, day, _) => _DayCircle(
          day: day,
          border: scheme.primary,
          textColor: scheme.primary,
        ),
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          return Positioned(
            bottom: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in events.take(4))
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: eventColor(e.color),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dayList(BuildContext context) {
    final day = widget.selectedDay;
    final events = widget.store.eventsOn(day);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  fmtDayLong(day),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (!isSameDay(day, DateTime.now()))
                TextButton(
                  onPressed: () => _select(dateOnly(DateTime.now())),
                  child: const Text('Hoje'),
                ),
            ],
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Text(
                    'Sem eventos neste dia',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: events.length,
                  itemBuilder: (context, i) => _EventTile(
                    event: events[i],
                    day: day,
                    store: widget.store,
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= 840) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _calendar(context, fill: true),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: 360, child: _dayList(context)),
              ],
            );
          }
          return Column(
            children: [
              _calendar(context, fill: false),
              const Divider(height: 1),
              Expanded(child: _dayList(context)),
            ],
          );
        },
      ),
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({
    required this.day,
    required this.textColor,
    this.fill,
    this.border,
  });

  final DateTime day;
  final Color textColor;
  final Color? fill;
  final Color? border;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border!, width: 1.5),
      ),
      child: Text('${day.day}', style: TextStyle(color: textColor)),
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.day,
    required this.store,
  });

  final Event event;
  final DateTime day;
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
