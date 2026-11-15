// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

/// Calendário de uma semana, mostrado ao lado do formulário de edição.
///
/// [draft] é o evento a ser editado, tal como está no formulário: aparece
/// realçado e acompanha as alterações em direto.
class WeekPanel extends StatelessWidget {
  const WeekPanel({
    super.key,
    required this.store,
    required this.draft,
    required this.onDayTap,
    this.anchor,
  });

  final Store store;
  final Event draft;

  /// Tocar num dia passa o evento para esse dia (`null` = desativado).
  final ValueChanged<DateTime>? onDayTap;

  /// Dia cuja semana é mostrada; por omissão, o início do evento.
  final DateTime? anchor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = anchor ?? draft.start;
    final monday = DateTime(s.year, s.month, s.day - (s.weekday - 1));
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final today = dateOnly(DateTime.now());

    List<Event> eventsOn(DateTime day) {
      final list = [
        for (final e in store.eventsOn(day))
          if (e.id != draft.id) e,
        if (draft.occursOn(day)) draft,
      ];
      list.sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        final ta = a.start.hour * 60 + a.start.minute;
        final tb = b.start.hour * 60 + b.start.minute;
        return ta - tb;
      });
      return list;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Semana de ${fmtDateShort(monday)} – ${fmtDateShort(sunday)} '
            '${sunday.year}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth / 7 < 90;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: _day(
                              context,
                              DateTime(
                                monday.year,
                                monday.month,
                                monday.day + i,
                              ),
                              today,
                              eventsOn,
                              compact,
                              scheme,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _day(
    BuildContext context,
    DateTime day,
    DateTime today,
    List<Event> Function(DateTime) eventsOn,
    bool compact,
    ColorScheme scheme,
  ) {
    final isToday = day == today;
    final active = draft.occursOn(day);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDayTap == null ? null : () => onDayTap!(day),
      child: Container(
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.08) : null,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.5),
            right: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fmtWeekday(day),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Center(
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday ? scheme.primary : null,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active || isToday
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: isToday ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final e in eventsOn(day))
              EventChipBox(
                event: e,
                day: day,
                compact: compact,
                highlight: e.id == draft.id,
              ),
          ],
        ),
      ),
    );
  }
}
