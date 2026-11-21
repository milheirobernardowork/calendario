// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../task_sections.dart';
import '../store.dart';
import 'common.dart';
import 'task_edit.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key, required this.store});

  final Store store;

  static const _minColumn = 250.0;

  /// Como cria uma tarefa o campo de cada coluna.
  Task _newTask(String column, String title, DateTime today) => Task(
    id: newId(),
    title: title,
    active: column == 'Ativas',
    future: column == 'Futuras',
    updatedAt: DateTime.now().toUtc(),
  );

  @override
  Widget build(BuildContext context) {
    return StoreListener(
      listenable: store,
      builder: (context) {
        final today = dateOnly(DateTime.now());
        final all = store.tasks;
        // Uma coluna por tipo: Ativas, Por Fazer e Futuras. As concluídas
        // são eliminadas.
        final columns = taskSections(all, today);
        return LayoutBuilder(
          builder: (context, box) {
            Widget column(int i) {
              final (name, items) = columns[i];
              return _TaskColumn(
                name: name,
                tasks: items,
                store: store,
                today: today,
                onAdd: (title) => store.saveTask(_newTask(name, title, today)),
              );
            }

            final fits = box.maxWidth / columns.length >= _minColumn;
            if (fits) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns.length; i++)
                    Expanded(child: column(i)),
                ],
              );
            }
            // Ecrã estreito: uma coluna de cada vez, a deslizar para o lado
            // (a seguinte espreita à direita).
            return PageView.builder(
              controller: PageController(viewportFraction: 0.88),
              padEnds: false,
              itemCount: columns.length,
              itemBuilder: (context, i) => column(i),
            );
          },
        );
      },
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.name,
    required this.tasks,
    required this.store,
    required this.today,
    this.onAdd,
  });

  final String name;
  final List<Task> tasks;
  final Store store;
  final DateTime today;
  final ValueChanged<String>? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${tasks.length}',
                  style: TextStyle(color: scheme.outline, fontSize: 15),
                ),
              ],
            ),
          ),
          if (onAdd != null) QuickAddTask(hint: 'Nova tarefa…', onAdd: onAdd!),
          Expanded(
            child: tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nada aqui',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final t in tasks)
                        TaskTile(
                          task: t,
                          store: store,
                          today: today,
                          inColumn: true,
                        ),
                    ],
                  ),
          ),
        ],
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
    this.inColumn = false,
  });

  final Task task;
  final Store store;
  final DateTime today;

  /// Versão estreita (painel lateral do calendário): sem botões à direita.
  final bool compact;

  /// Numa coluna estreita: botões mais pequenos.
  final bool inColumn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = task.due;
    final overdue = !task.done && due != null && due.isBefore(today);
    final flag = task.done ? null : priorityColor(task.priority);
    return ListTile(
      dense: compact,
      horizontalTitleGap: compact || inColumn ? 4 : null,
      contentPadding: compact
          ? const EdgeInsets.only(left: 4, right: 12)
          : inColumn
          ? const EdgeInsets.only(left: 2, right: 6)
          : null,
      leading: Checkbox(
        value: task.done,
        shape: const CircleBorder(),
        side: flag == null ? null : BorderSide(color: flag, width: 2),
        onChanged: (_) => completeTask(context, store, task),
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
      trailing: compact ? null : _buttons(context, scheme, flag),
      onTap: () => openTaskEditor(context, store, task: task),
    );
  }

  /// Prioridade e botões Futura / Ativa / Eliminar.
  Widget _buttons(BuildContext context, ColorScheme scheme, Color? flag) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (flag != null)
          Tooltip(
            message: 'Prioridade ${priorityNames[task.priority].toLowerCase()}',
            child: Icon(Icons.flag, color: flag, size: inColumn ? 16 : 20),
          ),
        IconButton(
          tooltip: task.future ? 'Deixar de ser futura' : 'Marcar como futura',
          isSelected: task.future,
          icon: Icon(Icons.schedule, color: scheme.outline),
          selectedIcon: Icon(Icons.schedule, color: scheme.primary),
          onPressed: () => store.toggleFuture(task),
        ),
        IconButton(
          tooltip: task.active ? 'Deixar de ser ativa' : 'Marcar como ativa',
          isSelected: task.active,
          icon: Icon(Icons.bolt_outlined, color: scheme.outline),
          selectedIcon: const Icon(Icons.bolt, color: Color(0xFFF2A100)),
          onPressed: () => store.toggleActive(task),
        ),
        IconButton(
          tooltip: 'Eliminar',
          icon: Icon(Icons.delete_outline, color: scheme.outline),
          onPressed: () {
            store.deleteTask(task);
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text('"${task.title}" eliminada'),
                // Desaparece sozinha ao fim de 4 s (e tem o X para fechar já).
                persist: false,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Anular',
                  onPressed: () => store.restoreTask(task),
                ),
              ),
            );
          },
        ),
      ],
    );
    if (!inColumn) return row;
    // Numa coluna estreita, botões mais pequenos para caber o título.
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          iconSize: 18,
          minimumSize: const Size(28, 28),
          padding: const EdgeInsets.all(4),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: row,
    );
  }
}

/// Campo pequeno para criar uma tarefa só com o título.
class QuickAddTask extends StatefulWidget {
  const QuickAddTask({super.key, required this.hint, required this.onAdd});

  final String hint;
  final ValueChanged<String> onAdd;

  @override
  State<QuickAddTask> createState() => _QuickAddTaskState();
}

class _QuickAddTaskState extends State<QuickAddTask> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _text.text.trim();
    if (title.isEmpty) return;
    widget.onAdd(title);
    _text.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    child: TextField(
      controller: _text,
      focusNode: _focus,
      textCapitalization: TextCapitalization.sentences,
      onSubmitted: (_) => _submit(),
      // Quem tira o foco é o calendário, ao ser clicado (ver os atalhos).
      onTapOutside: (_) {},
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.add, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    ),
  );
}

/// Concluir uma tarefa elimina-a (com "Anular" durante uns segundos).
void completeTask(BuildContext context, Store store, Task task) {
  store.deleteTask(task);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('"${task.title}" concluída'),
      persist: false,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Anular',
        onPressed: () => store.restoreTask(task),
      ),
    ),
  );
}
