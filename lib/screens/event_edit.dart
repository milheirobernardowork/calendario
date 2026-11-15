// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'week_panel.dart';

Future<void> openEventEditor(
  BuildContext context,
  Store store, {
  Event? event,
  DateTime? day,
  String? category,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EventEditScreen(
        store: store,
        event: event,
        day: day,
        category: category,
      ),
    ),
  );
}

class EventEditScreen extends StatefulWidget {
  const EventEditScreen({
    super.key,
    required this.store,
    this.event,
    this.day,
    this.category,
  });

  final Store store;
  final Event? event;

  /// Dia em que se tocou. Numa série, indica a ocorrência a editar.
  final DateTime? day;

  /// Coluna da página Eventos já escolhida para um evento novo.
  final String? category;

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
  String? _category;

  /// Numa série: dia da ocorrência aberta. Com [_wholeSeries] a falso, só
  /// essa ocorrência é alterada.
  DateTime? _occurrence;
  bool _wholeSeries = false;

  // Repetição.
  bool _repeat = false;
  String _unit = 'week';
  Set<int> _weekdays = {};
  String _endMode = 'never'; // never | date | count
  DateTime? _until;
  final _interval = TextEditingController(text: '1');
  final _count = TextEditingController(text: '10');

  /// Dia cuja semana aparece no painel: o dia em que se tocou no calendário,
  /// até a data de início ser alterada.
  DateTime? _anchor;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    // O painel da semana mostra o título em direto.
    _title.addListener(() => setState(() {}));
    if (e != null) {
      _allDay = e.allDay;
      _color = e.color;
      _category = e.category;
      _anchor = widget.day;
      if (e.recurrence != null) {
        _occurrence = e.occurrenceStartOn(widget.day ?? e.start);
      }
      // Por omissão edita-se só a ocorrência em que se tocou.
      _wholeSeries = _occurrence == null;
      _loadDates();
      final r = e.recurrence;
      if (r != null) {
        _repeat = true;
        _unit = r.unit;
        _interval.text = '${r.interval}';
        _weekdays = {...r.weekdays};
        _until = r.until;
        if (r.count != null) _count.text = '${r.count}';
        _endMode = r.count != null
            ? 'count'
            : r.until != null
            ? 'date'
            : 'never';
      }
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
      _category = widget.category;
    }
  }

  /// Datas do formulário: as da série ou as da ocorrência aberta.
  void _loadDates() {
    final e = widget.event!;
    final o = _instanceMode ? e.occurrenceAt(_occurrence!) : e;
    _start = o.start;
    _end = o.end;
  }

  /// A editar uma só ocorrência de uma série?
  bool get _instanceMode => _occurrence != null && !_wholeSeries;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  bool get _valid => _allDay
      ? !dateOnly(_end).isBefore(dateOnly(_start))
      : !_end.isBefore(_start);

  void _setStart(DateTime v) {
    // Mantém a duração ao mover o início.
    final length = _end.difference(_start);
    setState(() {
      _anchor = null;
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

  /// Id do evento único que substitui a ocorrência editada à parte.
  late final String _instanceId = newId();

  Recurrence? get _recurrence {
    if (!_repeat || _instanceMode) return null;
    final weekly = _unit == 'week';
    return Recurrence(
      unit: _unit,
      interval: (int.tryParse(_interval.text) ?? 1).clamp(1, 999),
      // Sem dias escolhidos, repete no dia da semana do início.
      weekdays: weekly ? {..._weekdays} : const {},
      until: _endMode == 'date' ? (_until ?? dateOnly(_start)) : null,
      count: _endMode == 'count'
          ? (int.tryParse(_count.text) ?? 1).clamp(1, 9999)
          : null,
      // Ocorrências já retiradas da série mantêm-se retiradas.
      exdates: widget.event?.recurrence?.exdates ?? const {},
    );
  }

  Future<void> _pickUntil() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _until ?? _start,
      firstDate: dateOnly(_start),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null) setState(() => _until = dateOnly(d));
  }

  Widget _numberField(TextEditingController c) => SizedBox(
    width: 76,
    child: TextField(
      controller: c,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      style: const TextStyle(fontSize: 17),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 14),
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget _choice(
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) => DropdownButton<String>(
    value: value,
    style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17),
    items: [
      for (final o in options.entries)
        DropdownMenuItem(value: o.key, child: Text(o.value)),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );

  Widget _repeatLabel(String text) => SizedBox(
    width: 76,
    child: Text(text, style: const TextStyle(fontSize: 16)),
  );

  List<Widget> _repeatSection(BuildContext context) {
    const dayNames = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    // Sem escolha explícita, fica marcado o dia da semana do início.
    final days = _weekdays.isEmpty ? {_start.weekday} : _weekdays;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Repetir', style: TextStyle(fontSize: 17)),
        value: _repeat,
        onChanged: (v) => setState(() => _repeat = v),
      ),
      if (_repeat) ...[
        Row(
          children: [
            _repeatLabel('a cada'),
            _numberField(_interval),
            const SizedBox(width: 12),
            _choice(_unit, const {
              'day': 'dias',
              'week': 'semanas',
              'month': 'meses',
              'year': 'anos',
            }, (v) => setState(() => _unit = v)),
          ],
        ),
        if (_unit == 'week') ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _repeatLabel('em'),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(
                          dayNames[d - 1],
                          style: const TextStyle(fontSize: 15),
                        ),
                        showCheckmark: false,
                        selected: days.contains(d),
                        onSelected: (on) => setState(() {
                          final next = {...days};
                          on ? next.add(d) : next.remove(d);
                          // Tem de ficar pelo menos um dia.
                          if (next.isNotEmpty) _weekdays = next;
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            _repeatLabel('termina'),
            _choice(_endMode, const {
              'never': 'nunca',
              'date': 'numa data',
              'count': 'após',
            }, (v) => setState(() => _endMode = v)),
            const SizedBox(width: 12),
            if (_endMode == 'date')
              Flexible(
                child: FilledButton.tonal(
                  style: bigButton,
                  onPressed: _pickUntil,
                  child: Text(
                    fmtDate(_until ?? dateOnly(_start)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (_endMode == 'count') ...[
              _numberField(_count),
              const SizedBox(width: 8),
              const Text('vezes', style: TextStyle(fontSize: 16)),
            ],
          ],
        ),
      ],
    ];
  }

  /// O evento tal como está no formulário.
  Event get _draft {
    final title = _title.text.trim();
    return Event(
      id: _instanceMode ? _instanceId : _id,
      title: title.isEmpty ? '(Sem título)' : title,
      notes: _notes.text.trim(),
      start: _allDay ? dateOnly(_start) : _start,
      end: _allDay ? dateOnly(_end) : _end,
      allDay: _allDay,
      color: _color,
      recurrence: _recurrence,
      category: _category,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _save() {
    if (!_valid) return;
    if (_instanceMode) {
      // A ocorrência sai da série e passa a evento único.
      widget.store.excludeOccurrence(widget.event!, _occurrence!);
    }
    widget.store.saveEvent(_draft);
    Navigator.pop(context);
  }

  /// Tocar num dia do painel da semana passa o evento para esse dia.
  void _moveToDay(DateTime day) => _setStart(
    DateTime(day.year, day.month, day.day, _start.hour, _start.minute),
  );

  Future<void> _delete() async {
    if (_instanceMode) {
      if (!await confirmDelete(context, 'só este dia da série')) return;
      widget.store.excludeOccurrence(widget.event!, _occurrence!);
      if (mounted) Navigator.pop(context);
      return;
    }
    final series = widget.event!.recurrence != null;
    if (!await confirmDelete(context, series ? 'a série inteira' : 'evento')) {
      return;
    }
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
          if (_occurrence != null) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: bigButton,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.event),
                  label: Text('Só ${fmtDateShort(_occurrence!)}'),
                ),
                const ButtonSegment(
                  value: true,
                  icon: Icon(Icons.repeat),
                  label: Text('Toda a série'),
                ),
              ],
              selected: {_wholeSeries},
              onSelectionChanged: (s) => setState(() {
                _wholeSeries = s.first;
                _anchor = _occurrence;
                _loadDates();
              }),
            ),
            const SizedBox(height: 8),
          ],
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
          const SizedBox(height: 8),
          if (!_instanceMode) ..._repeatSection(context),
          const SizedBox(height: 8),
          _categoryRow(),
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

  /// Escolha da coluna da página Eventos.
  Widget _categoryRow() {
    final cats = widget.store.categories;
    final value = cats.any((c) => c.id == _category) ? _category : null;
    return Row(
      children: [
        const Icon(Icons.emoji_events_outlined),
        const SizedBox(width: 12),
        const Text('Eventos', style: TextStyle(fontSize: 17)),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButton<String?>(
            isExpanded: true,
            value: value,
            style: Theme.of(context).textTheme.bodyLarge!
                .copyWith(fontSize: 17),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Nenhuma coluna'),
              ),
              for (final c in cats)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    final week = ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => WeekPanel(
        store: widget.store,
        draft: _draft,
        anchor: _anchor,
        // A ocorrência editada à parte não aparece também como parte da série.
        hide: _instanceMode
            ? (e, day) =>
                  e.id == widget.event!.id &&
                  e.occurrenceStartOn(day) == _occurrence
            : null,
        // Numa série, tocar num dia não muda a data de início.
        onDayTap: _repeat && !_instanceMode ? null : _moveToDay,
      ),
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
