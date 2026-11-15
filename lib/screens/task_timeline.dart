// ignore_for_file: deprecated_member_use

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'task_edit.dart';

/// Tarefas com data dispostas numa linha do tempo horizontal: uma coluna por
/// dia, que se percorre para trás e para a frente.
class TaskTimeline extends StatefulWidget {
  const TaskTimeline({super.key, required this.store, this.visit = 0});

  final Store store;

  /// Muda sempre que se entra na página: volta a pôr hoje ao centro.
  final int visit;

  @override
  State<TaskTimeline> createState() => _TaskTimelineState();
}

class _TaskTimelineState extends State<TaskTimeline> {
  static final _origin = DateTime(2000);
  static final _count = daysBetween(_origin, DateTime(2101));

  static DateTime _dayAt(int i) => DateTime(2000, 1, 1 + i);

  ScrollController? _scroll;
  double _extent = 0;

  /// Índice do primeiro dia à vista.
  late int _first = daysBetween(_origin, DateTime.now());

  /// Número de dias à vista (sempre ímpar, para hoje ficar ao centro).
  int _visible = 1;

  /// Dia para onde a animação em curso vai (roda do rato).
  int? _target;

  int get _todayIndex => daysBetween(_origin, DateTime.now());

  /// Primeiro dia à vista para que [index] fique ao centro.
  int _centered(int index) => index - _visible ~/ 2;

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final d = (ev as PointerScrollEvent).scrollDelta;
      final v = d.dy != 0 ? d.dy : d.dx;
      if (v == 0) return;
      _goTo((_target ?? _first) + (v > 0 ? 1 : -1));
    });
  }

  @override
  void didUpdateWidget(TaskTimeline old) {
    super.didUpdateWidget(old);
    if (old.visit != widget.visit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _scroll;
        if (mounted && c != null && c.hasClients) {
          c.jumpTo(_centered(_todayIndex) * _extent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final i = (_scroll!.offset / _extent).round();
    if (i != _first) setState(() => _first = i);
  }

  void _goTo(int index) {
    final c = _scroll;
    if (c == null) return;
    _target = index;
    c
        .animateTo(
          index * _extent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (_target == index) _target = null;
        });
  }

  /// Depois de arrastar, alinha pela coluna mais próxima.
  bool _snap(ScrollEndNotification n) {
    final target = (n.metrics.pixels / _extent).round() * _extent;
    if (_target == null && (target - n.metrics.pixels).abs() > 0.5) {
      Future.microtask(() => _goTo((target / _extent).round()));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StoreListener(
      listenable: widget.store,
      builder: (context) {
        final byDay = <DateTime, List<Task>>{};
        for (final t in widget.store.tasks) {
          if (t.due != null) (byDay[t.due!] ??= []).add(t);
        }
        for (final list in byDay.values) {
          list.sort((a, b) {
            if (a.done != b.done) return a.done ? 1 : -1;
            if (a.priority != b.priority) return b.priority - a.priority;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
        }
        final today = dateOnly(DateTime.now());

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Dia anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _goTo(_first - 1),
                  ),
                  IconButton(
                    tooltip: 'Dia seguinte',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _goTo(_first + 1),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      fmtMonth(_dayAt(_first + _visible ~/ 2)),
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _goTo(_centered(_todayIndex)),
                    child: const Text('Hoje'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  var visible = (box.maxWidth / 170).floor().clamp(1, 7);
                  if (visible.isEven) visible++;
                  _visible = visible;
                  final extent = box.maxWidth / visible;
                  if (_scroll == null) {
                    // Ao entrar na página, hoje aparece ao centro.
                    _first = _centered(_todayIndex);
                    _scroll = ScrollController(
                      initialScrollOffset: _first * extent,
                    )..addListener(_onScroll);
                  } else if (extent != _extent) {
                    // A janela mudou de tamanho: manter o mesmo dia à vista.
                    final first = _first;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scroll!.jumpTo(first * _extent);
                    });
                  }
                  _extent = extent;
                  return Listener(
                    onPointerSignal: _onWheel,
                    child: NotificationListener<ScrollEndNotification>(
                      onNotification: _snap,
                      child: ScrollConfiguration(
                        // Permite arrastar a linha do tempo também com o rato.
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: PointerDeviceKind.values.toSet(),
                          scrollbars: false,
                        ),
                        child: ListView.builder(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          itemExtent: extent,
                          itemCount: _count,
                          itemBuilder: (context, i) {
                            final day = _dayAt(i);
                            return _DayColumn(
                              day: day,
                              today: today,
                              tasks: byDay[day] ?? const [],
                              store: widget.store,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.today,
    required this.tasks,
    required this.store,
  });

  final DateTime day;
  final DateTime today;
  final List<Task> tasks;
  final Store store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = day == today;
    final past = day.isBefore(today);
    final accent = isToday ? scheme.primary : scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  color: isToday ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  day.day == 1
                      ? '${fmtWeekday(day)} · ${fmtDateShort(day).split(' ').last}'
                      : isToday
                      ? '${fmtWeekday(day)} · hoje'
                      : fmtWeekday(day),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: accent),
                ),
              ),
              IconButton(
                tooltip: 'Nova tarefa neste dia',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => openTaskEditor(context, store, due: day),
              ),
            ],
          ),
        ),
        // A linha do tempo: contínua entre colunas, com um marco por dia.
        SizedBox(
          height: 14,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(height: 2, color: scheme.outlineVariant),
              Positioned(
                left: 12,
                child: Container(
                  width: isToday ? 14 : 10,
                  height: isToday ? 14 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday
                        ? scheme.primary
                        : tasks.isNotEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.surface,
                    border: Border.all(
                      color: isToday ? scheme.primary : scheme.outline,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isToday ? scheme.primary.withValues(alpha: 0.05) : null,
              border: Border(
                right: BorderSide(color: scheme.outlineVariant, width: 0.5),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 88),
              children: [
                for (final t in tasks)
                  _TaskCard(task: t, store: store, overdue: past && !t.done),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.store,
    required this.overdue,
  });

  final Task task;
  final Store store;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final flag = task.done ? null : priorityColor(task.priority);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openTaskEditor(context, store, task: task),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: flag ?? Colors.transparent, width: 3),
            ),
          ),
          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
          child: Row(
            children: [
              if (task.active && !task.done)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.bolt, size: 16, color: Color(0xFFF2A100)),
                ),
              Checkbox(
                value: task.done,
                shape: const CircleBorder(),
                visualDensity: VisualDensity.compact,
                onChanged: (_) => store.toggleTask(task),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    task.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      decoration: task.done ? TextDecoration.lineThrough : null,
                      color: task.done
                          ? scheme.outline
                          : overdue
                          ? scheme.error
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
