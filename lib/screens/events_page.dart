// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'event_edit.dart';

/// Página "Eventos": eventos importantes do calendário, arrumados em colunas
/// (ex.: "Corridas") e ordenados por data. São os mesmos eventos do
/// calendário, por isso qualquer alteração aparece nos dois sítios.
class EventsPage extends StatelessWidget {
  const EventsPage({super.key, required this.store});

  final Store store;

  static const _minColumn = 280.0;

  Future<void> _addColumn(BuildContext context) async {
    final name = await _askName(context, 'Nova coluna', '');
    if (name != null) store.addCategory(name);
  }

  @override
  Widget build(BuildContext context) {
    return StoreListener(
      listenable: store,
      builder: (context) {
        final columns = store.categories;
        final today = dateOnly(DateTime.now());
        return LayoutBuilder(
          builder: (context, box) {
            // As colunas repartem a largura; se não couberem, ganham largura
            // fixa e a página desliza na horizontal.
            final count = columns.length + 1; // + botão "Nova coluna"
            final fits = box.maxWidth / count >= _minColumn;
            final width = fits
                ? box.maxWidth / count
                : (box.maxWidth < _minColumn + 40
                      ? box.maxWidth - 32
                      : _minColumn);
            final children = [
              for (final c in columns)
                SizedBox(
                  width: width,
                  child: _Column(column: c, store: store, today: today),
                ),
              SizedBox(
                width: fits ? width : 200,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      style: bigButton,
                      onPressed: () => _addColumn(context),
                      icon: const Icon(Icons.view_column_outlined),
                      label: const Text('Nova coluna'),
                    ),
                  ),
                ),
              ),
            ];
            return fits
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: children,
                  );
          },
        );
      },
    );
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void done() {
        final v = text.text.trim();
        Navigator.pop(context, v.isEmpty ? null : v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nome da coluna'),
          onSubmitted: (_) => done(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(onPressed: done, child: const Text('Guardar')),
        ],
      );
    },
  );
}

/// Um evento da coluna, com a data em que acontece (a próxima, se repetir).
typedef _Entry = ({Event event, DateTime date, bool past});

class _Column extends StatelessWidget {
  const _Column({
    required this.column,
    required this.store,
    required this.today,
  });

  final EventColumn column;
  final Store store;
  final DateTime today;

  List<_Entry> get _entries {
    final list = <_Entry>[];
    for (final e in store.events) {
      if (e.category != column.id) continue;
      final next = e.nextOccurrence(today);
      list.add(
        next != null
            ? (event: e, date: next, past: false)
            : (event: e, date: dateOnly(e.start), past: true),
      );
    }
    return list;
  }

  Future<void> _menu(BuildContext context, String action) async {
    if (action == 'rename') {
      final name = await _askName(context, 'Mudar o nome', column.name);
      if (name != null) store.renameCategory(column, name);
    } else if (action == 'delete') {
      if (await confirmDelete(context, 'a coluna "${column.name}"')) {
        store.deleteCategory(column);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _entries;
    // Próximos por ordem de data; os que já passaram vão para o fim.
    final upcoming = entries.where((x) => !x.past).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final past = entries.where((x) => x.past).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  column.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${upcoming.length}',
                style: TextStyle(color: scheme.outline, fontSize: 16),
              ),
              IconButton(
                tooltip: 'Novo evento em ${column.name}',
                icon: const Icon(Icons.add),
                onPressed: () =>
                    openEventEditor(context, store, category: column.id),
              ),
              PopupMenuButton<String>(
                onSelected: (a) => _menu(context, a),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Mudar o nome')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar coluna'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Sem eventos. No editor de um evento, escolhe a coluna '
                '"${column.name}" para o pôr aqui.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline),
              ),
            ),
          for (final x in upcoming) _Card(entry: x, store: store, today: today),
          if (past.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
              child: Text(
                'Já passaram',
                style: theme.textTheme.labelLarge!.copyWith(
                  color: scheme.outline,
                ),
              ),
            ),
            for (final x in past)
              Opacity(
                opacity: 0.55,
                child: _Card(entry: x, store: store, today: today),
              ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.entry, required this.store, required this.today});

  final _Entry entry;
  final Store store;
  final DateTime today;

  String get _countdown {
    final n = daysBetween(today, entry.date);
    if (n == 0) return 'Hoje';
    if (n == 1) return 'Amanhã';
    if (n > 1) return 'Daqui a $n dias';
    if (n == -1) return 'Ontem';
    return 'Há ${-n} dias';
  }

  @override
  Widget build(BuildContext context) {
    final e = entry.event;
    final color = eventColor(e.color);
    final fg = onColor(color);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openEventEditor(context, store, event: e, day: entry.date),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.title,
                style: TextStyle(
                  color: fg,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                e.allDay
                    ? fmtDate(entry.date)
                    : '${fmtDate(entry.date)} · ${fmtTime(e.start)}',
                style: TextStyle(color: fg.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 2),
              Text(
                _countdown,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
