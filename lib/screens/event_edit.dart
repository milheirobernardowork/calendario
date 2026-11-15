// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

Future<void> openEventEditor(
  BuildContext context,
  Store store, {
  Event? event,
  DateTime? day,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EventEditScreen(store: store, event: event, day: day),
    ),
  );
}

class EventEditScreen extends StatefulWidget {
  const EventEditScreen({super.key, required this.store, this.event, this.day});

  final Store store;
  final Event? event;
  final DateTime? day;

  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  late int _color;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    if (e != null) {
      _start = e.start;
      _end = e.end;
      _allDay = e.allDay;
      _color = e.color;
    } else {
      final now = DateTime.now();
      final day = widget.day ?? dateOnly(now);
      // Hoje: próxima hora certa. Outro dia: 9h.
      final hour = dateOnly(now) == dateOnly(day) ? (now.hour + 1) : 9;
      _start = DateTime(
        day.year,
        day.month,
        day.day,
      ).add(Duration(hours: hour));
      _end = _start.add(const Duration(hours: 1));
      _allDay = false;
      _color = 0;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid => _allDay
      ? !dateOnly(_end).isBefore(dateOnly(_start))
      : !_end.isBefore(_start);

  void _setStart(DateTime v) {
    // Mantém a duração ao mover o início.
    final length = _end.difference(_start);
    setState(() {
      _start = v;
      _end = v.add(length.isNegative ? Duration.zero : length);
    });
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d == null) return;
    final v = DateTime(d.year, d.month, d.day, current.hour, current.minute);
    start ? _setStart(v) : setState(() => _end = v);
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (t == null) return;
    final v = DateTime(
      current.year,
      current.month,
      current.day,
      t.hour,
      t.minute,
    );
    start ? _setStart(v) : setState(() => _end = v);
  }

  void _save() {
    if (!_valid) return;
    final old = widget.event;
    final title = _title.text.trim();
    widget.store.saveEvent(
      Event(
        id: old?.id ?? newId(),
        title: title.isEmpty ? '(Sem título)' : title,
        notes: _notes.text.trim(),
        start: _allDay ? dateOnly(_start) : _start,
        end: _allDay ? dateOnly(_end) : _end,
        allDay: _allDay,
        color: _color,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'evento')) return;
    widget.store.deleteEvent(widget.event!);
    if (mounted) Navigator.pop(context);
  }

  Widget _whenRow(String label, {required bool start}) {
    final v = start ? _start : _end;
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _pickDate(start: start),
              child: Text(fmtDate(v)),
            ),
          ),
        ),
        if (!_allDay)
          TextButton(
            onPressed: () => _pickTime(start: start),
            child: Text(fmtTime(v)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event == null ? 'Novo evento' : 'Editar evento'),
        actions: [
          if (widget.event != null)
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
              autofocus: widget.event == null,
              textCapitalization: TextCapitalization.sentences,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(hintText: 'Título'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dia inteiro'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            _whenRow('Início', start: true),
            _whenRow('Fim', start: false),
            if (!_valid)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'O fim tem de ser depois do início.',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                for (var i = 0; i < eventColors.length; i++)
                  Tooltip(
                    message: eventColorNames[i],
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: eventColors[i],
                          shape: BoxShape.circle,
                        ),
                        child: _color == i
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
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
