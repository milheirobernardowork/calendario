// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

/// Workspace: pastas com páginas de notas (títulos, texto, listas, tarefas,
/// tabelas e links). Sincroniza como o resto, pela tabela `pages`.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.store});

  final Store store;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  String? _selected;
  final _collapsed = <String>{};

  Store get store => widget.store;

  void _newPage({String? folder}) {
    final current = store.pageById(_selected);
    final inFolder = folder ?? current?.folder ?? '';
    final siblings = store.pages.where((p) => p.folder == inFolder);
    final page = WorkPage(
      id: newId(),
      title: 'Nova página',
      folder: inFolder,
      color: current?.color ?? defaultEventColor,
      position: siblings.isEmpty
          ? 0
          : siblings.map((p) => p.position).reduce((a, b) => a > b ? a : b) + 1,
      blocks: [
        {'id': newId(), 'type': 'text', 'text': ''},
      ],
      updatedAt: DateTime.now().toUtc(),
    );
    store.savePage(page);
    setState(() => _selected = page.id);
  }

  Future<void> _newFolder() async {
    final name = await _askText(context, 'Nova pasta', '', 'Nome da pasta');
    if (name != null) _newPage(folder: name);
  }

  Future<void> _renameFolder(String folder) async {
    final name = await _askText(context, 'Mudar o nome', folder, 'Nome');
    if (name != null && name != folder) store.renameFolder(folder, name);
  }

  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final byFolder = <String, List<WorkPage>>{};
    for (final p in store.pages) {
      (byFolder[p.folder] ??= []).add(p);
    }
    Widget pageTile(WorkPage p) {
      final selected = p.id == _selected;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _selected = p.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 9, 8, 9),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: eventColor(p.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.title.trim().isEmpty ? 'Sem título' : p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Workspace',
                  style: theme.textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Nova pasta',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _newFolder,
              ),
              IconButton(
                tooltip: 'Nova página',
                icon: const Icon(Icons.add),
                onPressed: _newPage,
              ),
            ],
          ),
        ),
        if (byFolder.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Cria uma pasta (ex.: ATEC) e páginas dentro dela para '
              'guardar notas, tabelas e links.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
          ),
        // Páginas sem pasta primeiro, depois cada pasta.
        for (final p in byFolder[''] ?? const <WorkPage>[]) pageTile(p),
        for (final entry in byFolder.entries)
          if (entry.key.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() {
                _collapsed.contains(entry.key)
                    ? _collapsed.remove(entry.key)
                    : _collapsed.add(entry.key);
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 4, 4),
                child: Row(
                  children: [
                    Icon(
                      _collapsed.contains(entry.key)
                          ? Icons.chevron_right
                          : Icons.expand_more,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: theme.textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      iconSize: 18,
                      tooltip: 'Pasta',
                      onSelected: (v) => v == 'new'
                          ? _newPage(folder: entry.key)
                          : _renameFolder(entry.key),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'new', child: Text('Nova página')),
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Mudar o nome'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!_collapsed.contains(entry.key))
              for (final p in entry.value) pageTile(p),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StoreListener(
      listenable: store,
      builder: (context) => LayoutBuilder(
        builder: (context, box) {
          final page = store.pageById(_selected);
          final editor = page == null
              ? null
              : _PageEditor(
                  key: ValueKey(page.id),
                  store: store,
                  page: page,
                  folders: {
                    for (final p in store.pages)
                      if (p.folder.isNotEmpty) p.folder,
                  }.toList()..sort(),
                  onBack: box.maxWidth < 840
                      ? () => setState(() => _selected = null)
                      : null,
                  onDeleted: () => setState(() => _selected = null),
                );
          if (box.maxWidth < 840) {
            // Telemóvel: a lista de páginas ou a página aberta.
            return editor ?? _sidebar(context);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 270, child: _sidebar(context)),
              const VerticalDivider(width: 1),
              Expanded(
                child:
                    editor ??
                    Center(
                      child: Text(
                        'Escolhe ou cria uma página',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<String?> _askText(
  BuildContext context,
  String title,
  String initial,
  String hint,
) {
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
          decoration: InputDecoration(hintText: hint),
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

// ------------------------------------------------------------------ editor

const _blockTypes = {
  'h1': 'Título',
  'h2': 'Subtítulo',
  'text': 'Texto',
  'bullet': 'Lista',
  'todo': 'Tarefa',
  'table': 'Tabela',
  'link': 'Link',
};

const _blockIcons = {
  'h1': Icons.title,
  'h2': Icons.text_fields,
  'text': Icons.notes,
  'bullet': Icons.format_list_bulleted,
  'todo': Icons.check_box_outlined,
  'table': Icons.table_chart_outlined,
  'link': Icons.link,
};

/// Um bloco em edição: os dados e os campos de texto que lhe pertencem.
class _Block {
  _Block(Map<String, dynamic> data)
    : id = data['id'] as String? ?? newId(),
      type = data['type'] as String? ?? 'text',
      checked = data['checked'] as bool? ?? false,
      text = TextEditingController(text: data['text'] as String? ?? ''),
      url = TextEditingController(text: data['url'] as String? ?? '') {
    final rows = data['rows'] as List?;
    cells = [
      for (final r
          in rows ??
              const [
                ['', ''],
                ['', ''],
              ])
        [for (final c in r as List) TextEditingController(text: '$c')],
    ];
  }

  final String id;
  String type;
  bool checked;
  final TextEditingController text;
  final TextEditingController url;
  late List<List<TextEditingController>> cells;

  int get columns => cells.isEmpty ? 0 : cells.first.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (type != 'table') 'text': text.text,
    if (type == 'todo') 'checked': checked,
    if (type == 'link') 'url': url.text.trim(),
    if (type == 'table')
      'rows': [
        for (final r in cells) [for (final c in r) c.text],
      ],
  };

  void dispose() {
    text.dispose();
    url.dispose();
    for (final r in cells) {
      for (final c in r) {
        c.dispose();
      }
    }
  }
}

class _PageEditor extends StatefulWidget {
  const _PageEditor({
    super.key,
    required this.store,
    required this.page,
    required this.folders,
    required this.onDeleted,
    this.onBack,
  });

  final Store store;
  final WorkPage page;
  final List<String> folders;
  final VoidCallback onDeleted;
  final VoidCallback? onBack;

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  late final _title = TextEditingController(text: widget.page.title);
  late final List<_Block> _blocks = [
    for (final b in widget.page.blocks) _Block(b),
  ];
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
    for (final b in _blocks) {
      _listen(b);
    }
  }

  void _listen(_Block b) {
    b.text.addListener(_changed);
    b.url.addListener(_changed);
    for (final r in b.cells) {
      for (final c in r) {
        c.addListener(_changed);
      }
    }
  }

  @override
  void dispose() {
    // Ao sair da página, grava logo o que faltar.
    if (_saveTimer?.isActive ?? false) _save();
    _saveTimer?.cancel();
    _title.dispose();
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  /// Grava meio segundo depois da última alteração.
  void _changed() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() {
    final p = widget.page;
    p.title = _title.text.trim();
    p.blocks = [for (final b in _blocks) b.toJson()];
    widget.store.savePage(p);
  }

  void _structureChanged() {
    setState(() {});
    _changed();
  }

  void _add(String type, {int? at}) {
    final b = _Block({'type': type});
    _listen(b);
    setState(() => _blocks.insert(at ?? _blocks.length, b));
    _changed();
  }

  void _remove(_Block b) {
    setState(() => _blocks.remove(b));
    b.dispose();
    _changed();
  }

  Future<void> _deletePage() async {
    if (!await confirmDelete(context, 'a página "${widget.page.title}"')) {
      return;
    }
    _saveTimer?.cancel();
    widget.store.deletePage(widget.page);
    widget.onDeleted();
  }

  Future<void> _chooseFolder() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mover para a pasta')),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('Sem pasta'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final f in widget.folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f),
                onTap: () => Navigator.pop(context, f),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Nova pasta…'),
              onTap: () => Navigator.pop(context, '\u0000new'),
            ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    var folder = value;
    if (value == '\u0000new') {
      final name = await _askText(context, 'Nova pasta', '', 'Nome da pasta');
      if (name == null) return;
      folder = name;
    }
    widget.page.folder = folder;
    _save();
    setState(() {});
  }

  Widget _colorDot() => PopupMenuButton<int>(
    tooltip: 'Cor',
    onSelected: (i) {
      widget.page.color = i;
      _save();
      setState(() {});
    },
    itemBuilder: (context) => [
      for (var i = 0; i < eventColors.length; i++)
        PopupMenuItem(
          value: i,
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: eventColors[i],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(eventColorNames[i]),
            ],
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: eventColor(widget.page.color),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folder = widget.page.folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  tooltip: 'Páginas',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (_saveTimer?.isActive ?? false) _save();
                    widget.onBack!();
                  },
                ),
              _colorDot(),
              Expanded(
                child: TextField(
                  controller: _title,
                  style: theme.textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Título da página',
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _chooseFolder,
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: Text(folder.isEmpty ? 'Sem pasta' : folder),
              ),
              IconButton(
                tooltip: 'Eliminar página',
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: _deletePage,
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 24),
            buildDefaultDragHandles: false,
            itemCount: _blocks.length,
            onReorder: (from, to) {
              setState(() {
                final b = _blocks.removeAt(from);
                _blocks.insert(to > from ? to - 1 : to, b);
              });
              _changed();
            },
            footer: _addBar(context),
            itemBuilder: (context, i) => _blockRow(context, i),
          ),
        ),
      ],
    );
  }

  Widget _addBar(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(36, 12, 0, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _blockTypes.entries)
          ActionChip(
            avatar: Icon(_blockIcons[t.key], size: 18),
            label: Text(t.value),
            onPressed: () => _add(t.key),
          ),
      ],
    ),
  );

  Widget _blockRow(BuildContext context, int i) {
    final b = _blocks[i];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: ValueKey(b.id),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableDragStartListener(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, right: 4),
            child: Icon(
              Icons.drag_indicator,
              size: 18,
              color: scheme.outlineVariant,
            ),
          ),
        ),
        Expanded(child: _blockBody(context, b)),
        PopupMenuButton<String>(
          tooltip: 'Bloco',
          iconSize: 18,
          icon: Icon(Icons.more_horiz, color: scheme.outline),
          onSelected: (v) {
            if (v == 'delete') {
              _remove(b);
            } else if (v.startsWith('add:')) {
              _add(v.substring(4), at: _blocks.indexOf(b) + 1);
            } else {
              b.type = v;
              _structureChanged();
            }
          },
          itemBuilder: (context) => [
            for (final t in _blockTypes.entries)
              if (t.key != b.type && t.key != 'table' && b.type != 'table')
                PopupMenuItem(
                  value: t.key,
                  child: Text('Transformar em ${t.value.toLowerCase()}'),
                ),
            const PopupMenuItem(
              value: 'add:text',
              child: Text('Novo bloco por baixo'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Eliminar', style: TextStyle(color: scheme.error)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c, {
    TextStyle? style,
    String hint = 'Escreve aqui…',
  }) => TextField(
    controller: c,
    maxLines: null,
    style: style,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration.collapsed(hintText: hint).copyWith(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      isDense: true,
    ),
  );

  Widget _blockBody(BuildContext context, _Block b) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (b.type) {
      case 'h1':
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _field(
            b.text,
            hint: 'Título',
            style: theme.textTheme.headlineSmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _field(
            b.text,
            hint: 'Subtítulo',
            style: theme.textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case 'bullet':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 10, 0),
              child: Text('•', style: TextStyle(fontSize: 16)),
            ),
            Expanded(child: _field(b.text, hint: 'Item')),
          ],
        );
      case 'todo':
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: b.checked,
              visualDensity: VisualDensity.compact,
              onChanged: (v) {
                b.checked = v ?? false;
                _structureChanged();
              },
            ),
            Expanded(
              child: _field(
                b.text,
                hint: 'Tarefa',
                style: b.checked
                    ? TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: scheme.outline,
                      )
                    : null,
              ),
            ),
          ],
        );
      case 'link':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Abrir',
                icon: Icon(Icons.open_in_new, color: scheme.primary),
                onPressed: () {
                  var u = b.url.text.trim();
                  if (u.isEmpty) return;
                  if (!u.contains('://')) u = 'https://$u';
                  launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(
                      b.text,
                      hint: 'Nome do link',
                      style: TextStyle(
                        color: scheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    _field(
                      b.url,
                      hint: 'https://…',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'table':
        return _table(context, b);
      default:
        return _field(b.text);
    }
  }

  Widget _table(BuildContext context, _Block b) {
    final scheme = Theme.of(context).colorScheme;
    void addRow() {
      final row = [for (var i = 0; i < b.columns; i++) TextEditingController()];
      for (final c in row) {
        c.addListener(_changed);
      }
      b.cells.add(row);
      _structureChanged();
    }

    void addColumn() {
      for (final r in b.cells) {
        r.add(TextEditingController()..addListener(_changed));
      }
      _structureChanged();
    }

    void removeRow() {
      if (b.cells.length <= 1) return;
      for (final c in b.cells.removeLast()) {
        c.dispose();
      }
      _structureChanged();
    }

    void removeColumn() {
      if (b.columns <= 1) return;
      for (final r in b.cells) {
        r.removeLast().dispose();
      }
      _structureChanged();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(180),
              border: TableBorder.all(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              children: [
                for (var r = 0; r < b.cells.length; r++)
                  TableRow(
                    // A primeira linha é o cabeçalho.
                    decoration: r == 0
                        ? BoxDecoration(color: scheme.surfaceContainerHigh)
                        : null,
                    children: [
                      for (final c in b.cells[r])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: TextField(
                            controller: c,
                            maxLines: null,
                            style: TextStyle(
                              fontWeight: r == 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            decoration:
                                const InputDecoration.collapsed(
                                  hintText: '',
                                ).copyWith(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  isDense: true,
                                ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: addRow,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Linha'),
              ),
              TextButton.icon(
                onPressed: addColumn,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Coluna'),
              ),
              TextButton.icon(
                onPressed: removeRow,
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('Linha'),
              ),
              TextButton.icon(
                onPressed: removeColumn,
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('Coluna'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
