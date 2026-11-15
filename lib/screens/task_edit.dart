// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

Future<void> openTaskEditor(
  BuildContext context,
  Store store, {
  Task? task,
  DateTime? due,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TaskEditScreen(store: store, task: task, due: due),
    ),
  );
}

class TaskEditScreen extends StatefulWidget {
  const TaskEditScreen({super.key, required this.store, this.task, this.due});

  final Store store;
  final Task? task;

  /// Data limite inicial de uma tarefa nova.
  final DateTime? due;

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _notes = TextEditingController(text: widget.task?.notes ?? '');
  late DateTime? _due = widget.task != null
      ? widget.task!.due
      // Tarefas novas ficam para hoje, a não ser que se indique outro dia.
      : (widget.due ?? dateOnly(DateTime.now()));
  late int _priority = widget.task?.priority ?? 0;
  late bool _done = widget.task?.done ?? false;
  late bool _active = widget.task?.active ?? false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().isNotEmpty;

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null) setState(() => _due = dateOnly(d));
  }

  void _save() {
    if (!_valid) return;
    widget.store.saveTask(
      Task(
        id: widget.task?.id ?? newId(),
        title: _title.text.trim(),
        notes: _notes.text.trim(),
        due: _due,
        done: _done,
        active: _active,
        priority: _priority,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'tarefa')) return;
    widget.store.deleteTask(widget.task!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Nova tarefa' : 'Editar tarefa'),
        actions: [
          if (widget.task != null)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _valid ? _save : null,
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: Centered(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              autofocus: widget.task == null,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(hintText: 'Título'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            if (widget.task != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Concluída'),
                value: _done,
                onChanged: (v) => setState(() => _done = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bolt),
              title: const Text('Ativa'),
              subtitle: const Text('Aparece no painel lateral do calendário'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(_due == null ? 'Sem data limite' : fmtDate(_due!)),
              onTap: _pickDue,
              trailing: _due == null
                  ? null
                  : IconButton(
                      tooltip: 'Remover data',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _due = null),
                    ),
            ),
            const SizedBox(height: 8),
            Text('Prioridade', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var i = 0; i < priorityNames.length; i++)
                  ButtonSegment(value: i, label: Text(priorityNames[i])),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notas',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
