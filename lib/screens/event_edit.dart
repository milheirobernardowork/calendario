// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'week_panel.dart';

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
    // O painel da semana mostra o título em direto.
    _title.addListener(() => setState(() {}));
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

  /// Id do evento em edição (um novo recebe já o seu, para o painel da
  /// semana o distinguir dos existentes).
  late final String _id = widget.event?.id ?? newId();

  /// O evento tal como está no formulário.
  Event get _draft {
    final title = _title.text.trim();
    return Event(
      id: _id,
      title: title.isEmpty ? '(Sem título)' : title,
      notes: _notes.text.trim(),
      start: _allDay ? dateOnly(_start) : _start,
      end: _allDay ? dateOnly(_end) : _end,
      allDay: _allDay,
      color: _color,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _save() {
    if (!_valid) return;
    widget.store.saveEvent(_draft);
    Navigator.pop(context);
  }

  /// Tocar num dia do painel da semana passa o evento para esse dia.
  void _moveToDay(DateTime day) => _setStart(
    DateTime(day.year, day.month, day.day, _start.hour, _start.minute),
  );

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'evento')) return;
    widget.store.deleteEvent(widget.event!);
    if (mounted) Navigator.pop(context);
  }

  Widget _whenRow(String label, {required bool start}) {
    final v = start ? _start : _end;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            child: FilledButton.tonal(
              style: bigButton,
              onPressed: () => _pickDate(start: start),
              child: Text(fmtDate(v), overflow: TextOverflow.ellipsis),
            ),
          ),
          if (!_allDay) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: bigButton,
              onPressed: () => _pickTime(start: start),
              child: Text(fmtTime(v)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Centered(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.event == null,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: const InputDecoration(
              hintText: 'Título',
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dia inteiro', style: TextStyle(fontSize: 17)),
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
                style: TextStyle(color: scheme.error, fontSize: 15),
              ),
            ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < eventColors.length; i++)
                Tooltip(
                  message: eventColorNames[i],
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: eventColors[i],
                        shape: BoxShape.circle,
                        border: _color == i
                            ? Border.all(color: scheme.onSurface, width: 3)
                            : null,
                      ),
                      child: _color == i
                          ? Icon(
                              Icons.check,
                              size: 24,
                              color: onColor(eventColors[i]),
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Notas',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (widget.event != null)
                OutlinedButton.icon(
                  style: bigButton.copyWith(
                    foregroundColor: WidgetStatePropertyAll(scheme.error),
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                ),
              TextButton(
                style: bigButton,
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: bigButton,
                onPressed: _valid ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    final week = ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) =>
          WeekPanel(store: widget.store, draft: _draft, onDayTap: _moveToDay),
    );
    // Com o teclado aberto (telemóvel) não sobra espaço para a semana.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(widget.event == null ? 'Novo evento' : 'Editar evento'),
      ),
      // Metade formulário, metade semana do evento: lado a lado em janelas
      // largas, um por cima do outro no telemóvel.
      body: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 840
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _form(context)),
                  VerticalDivider(width: 1, color: divider),
                  Expanded(child: week),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _form(context)),
                  if (!keyboard) ...[
                    Divider(height: 1, color: divider),
                    Expanded(child: week),
                  ],
                ],
              ),
      ),
    );
  }
}
