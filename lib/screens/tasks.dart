// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'task_edit.dart';
import 'task_timeline.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.store});

  final Store store;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _quick = TextEditingController();
  final _quickFocus = FocusNode();
  bool _showDone = false;
  bool _timeline = false;

  @override
  void dispose() {
    _quick.dispose();
    _quickFocus.dispose();
    super.dispose();
  }

  void _quickAdd() {
    final title = _quick.text.trim();
    if (title.isEmpty) return;
    widget.store.saveTask(
      Task(id: newId(), title: title, updatedAt: DateTime.now().toUtc()),
    );
    _quick.clear();
    _quickFocus.requestFocus();
  }

  /// Prioridade mais alta primeiro; depois data; depois título.
  static int _order(Task a, Task b) {
    if (a.priority != b.priority) return b.priority - a.priority;
    final ad = a.due, bd = b.due;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.checklist),
                label: Text('Lista'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.timeline),
                label: Text('Timeline'),
              ),
            ],
            selected: {_timeline},
            onSelectionChanged: (s) => setState(() => _timeline = s.first),
          ),
        ),
        Expanded(
          child: _timeline ? TaskTimeline(store: widget.store) : _list(context),
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final today = dateOnly(DateTime.now());
        final all = widget.store.tasks;
        final open = all.where((t) => !t.done).toList()..sort(_order);
        final done = all.where((t) => t.done).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final sections = <(String, List<Task>, bool)>[
          (
            'Atrasadas',
            open.where((t) => t.due != null && t.due!.isBefore(today)).toList(),
            true,
          ),
          ('Hoje', open.where((t) => t.due == today).toList(), false),
          (
            'Próximas',
            open.where((t) => t.due != null && t.due!.isAfter(today)).toList()
              ..sort((a, b) => a.due!.compareTo(b.due!)),
            false,
          ),
          ('Sem data', open.where((t) => t.due == null).toList(), false),
        ];

        final scheme = Theme.of(context).colorScheme;
        return Centered(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _quick,
                  focusNode: _quickFocus,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _quickAdd(),
                  decoration: InputDecoration(
                    hintText: 'Adicionar tarefa…',
                    prefixIcon: const Icon(Icons.add),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text(
                    'Ainda não tens tarefas',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.outline),
                  ),
                ),
              for (final (name, items, alert) in sections)
                if (items.isNotEmpty) ...[
                  _Header(
                    '$name · ${items.length}',
                    color: alert ? scheme.error : null,
                  ),
                  for (final t in items)
                    TaskTile(task: t, store: widget.store, today: today),
                ],
              if (done.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _showDone = !_showDone),
                  child: Row(
                    children: [
                      Expanded(child: _Header('Concluídas · ${done.length}')),
                      Padding(
                        padding: const EdgeInsets.only(right: 16, top: 8),
                        child: Icon(
                          _showDone ? Icons.expand_less : Icons.expand_more,
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showDone)
                  for (final t in done)
                    TaskTile(task: t, store: widget.store, today: today),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge!.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Linha de uma tarefa: concluir, marcar como ativa, abrir para editar.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.store,
    required this.today,
    this.compact = false,
  });

  final Task task;
  final Store store;
  final DateTime today;

  /// Versão estreita (painel lateral do calendário): sem botões à direita.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = task.due;
    final overdue = !task.done && due != null && due.isBefore(today);
    final flag = task.done ? null : priorityColor(task.priority);
    return ListTile(
      dense: compact,
      horizontalTitleGap: compact ? 4 : null,
      contentPadding: compact
          ? const EdgeInsets.only(left: 4, right: 12)
          : null,
      leading: Checkbox(
        value: task.done,
        shape: const CircleBorder(),
        side: flag == null ? null : BorderSide(color: flag, width: 2),
        onChanged: (_) => store.toggleTask(task),
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: task.done
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: scheme.outline,
              )
            : null,
      ),
      subtitle: due == null
          ? null
          : Text(
              due == today ? 'Hoje' : fmtDate(due),
              style: TextStyle(color: overdue ? scheme.error : null),
            ),
      trailing: compact
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (flag != null)
                  Tooltip(
                    message:
                        'Prioridade ${priorityNames[task.priority].toLowerCase()}',
                    child: Icon(Icons.flag, color: flag, size: 20),
                  ),
                IconButton(
                  tooltip: task.active
                      ? 'Deixar de ser ativa'
                      : 'Marcar como ativa',
                  isSelected: task.active,
                  icon: Icon(Icons.bolt_outlined, color: scheme.outline),
                  selectedIcon: const Icon(
                    Icons.bolt,
                    color: Color(0xFFF2A100),
                  ),
                  onPressed: () => store.toggleActive(task),
                ),
              ],
            ),
      onTap: () => openTaskEditor(context, store, task: task),
    );
  }
}
