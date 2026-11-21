// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'calendar.dart';

import 'dart:io' show File;

import 'package:url_launcher/url_launcher.dart';

import '../backups.dart';
import '../home_widget_sync.dart';
import '../updates.dart';
import 'event_edit.dart';
import 'events_page.dart';
import 'workspace.dart';
import 'task_edit.dart';
import 'tasks.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    this.userEmail,
    this.onSignOut,
  });

  final Store store;
  final String? userEmail;
  final Future<void> Function()? onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  DateTime _selectedDay = dateOnly(DateTime.now());

  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeWidgetSync.openTasks.addListener(_openTasks);
    if (HomeWidgetSync.openTasks.value > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goTab(1));
    }
    // Uns segundos depois de abrir, ver se há uma versão nova.
    if (updatesSupported) {
      installedVersion().then((v) {
        if (mounted) setState(() => _version = v);
      });
      Future<void>.delayed(
        const Duration(seconds: 5),
        () => _checkUpdates(silent: true),
      );
    }
  }

  String? _version;

  /// Janela das cópias de segurança: fazer uma agora ou repor uma antiga.
  Future<void> _showBackups() async {
    final backups = Backups.instance;
    if (backups == null) return;
    final dir = await backups.folder();
    var files = await backups.list();
    if (!mounted) return;
    String label(File f) {
      final name = f.uri.pathSegments.last;
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})')
          .firstMatch(name);
      return m == null ? name : '${m[3]}/${m[2]}/${m[1]} às ${m[4]}:${m[5]}';
    }

    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setInner) => AlertDialog(
          title: const Text('Cópias de segurança'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'É feita uma cópia a cada 12 horas enquanto a app está '
                  'aberta (e ao abrir, se a última for mais antiga). '
                  'Guardam-se as 14 mais recentes.',
                ),
                const SizedBox(height: 8),
                SelectableText(
                  dir.path,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(dialog).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                if (files.isEmpty) const Text('Ainda não há cópias.'),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in files)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(label(f)),
                          trailing: TextButton(
                            child: const Text('Repor'),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: dialog,
                                builder: (c) => AlertDialog(
                                  title: const Text('Repor esta cópia?'),
                                  content: Text(
                                    'Os eventos, tarefas e páginas da cópia de '
                                    '${label(f)} voltam a ficar como estavam '
                                    '(também no servidor). O que foi criado '
                                    'depois mantém-se.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Repor'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              await backups.restore(f);
                              if (dialog.mounted) Navigator.pop(dialog);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Cópia de ${label(f)} reposta.',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Fechar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Fazer cópia agora'),
              onPressed: () async {
                await backups.backupNow();
                final updated = await backups.list();
                setInner(() => files = updated);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Procura uma versão nova no GitHub. Com [silent], só diz alguma coisa
  /// se houver atualização.
  Future<void> _checkUpdates({bool silent = false}) async {
    final r = await checkForUpdate();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (r.hasUpdate) {
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(
        MaterialBanner(
          leading: const Icon(Icons.system_update),
          content: Text(
            'Há uma versão nova da WolfCal: ${r.latest}'
            '${r.latestDate == null ? '' : ', criada a ${fmtBuildDate(r.latestDate!)}'}'
            ' (tens a ${r.installed}).',
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text('Mais tarde'),
            ),
            FilledButton.icon(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                launchUrl(r.download!, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.download),
              label: const Text('Descarregar'),
            ),
          ],
        ),
      );
    } else if (!silent) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.error != null
                ? 'Não foi possível verificar: ${r.error}.'
                : 'Tens a versão mais recente (${r.installed}'
                      '${buildTime == null ? '' : ', criada a ${fmtBuildDate(buildTime!)}'}).',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomeWidgetSync.openTasks.removeListener(_openTasks);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ao voltar à app, ir buscar o que mudou nos outros dispositivos.
    if (state == AppLifecycleState.resumed) store.sync();
    // A app vai para segundo plano ou fechar: gravar já o que falta.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      store.flush();
    }
  }

  /// O widget de tarefas pediu para abrir a página Tarefas.
  void _openTasks() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _goTab(1);
  }

  void _goTab(int i) => setState(() {
    _tab = i;
  });

  Future<void> _add() async {
    if (_tab == 0) {
      await openEventEditor(context, store, day: _selectedDay);
    } else if (_tab == 2) {
      final cats = store.categories;
      await openEventEditor(
        context,
        store,
        category: cats.isEmpty ? null : cats.first.id,
      );
    } else {
      await openTaskEditor(context, store);
    }
  }

  Future<void> _confirmSignOut() async {
    final pending = store.pendingChanges;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminar sessão?'),
        content: Text(
          pending > 0
              ? 'Há $pending alteração(ões) ainda não sincronizada(s) que '
                    'serão perdidas.'
              : 'Os dados continuam guardados na tua conta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Terminar sessão'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.onSignOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(
      index: _tab,
      children:
          [
            CalendarPage(
              store: store,
              selectedDay: _selectedDay,
              onDaySelected: (d) => setState(() => _selectedDay = d),
              onSwipeRight: () => _goTab(1),
            ),
            TasksPage(store: store),
            EventsPage(store: store),
            WorkspacePage(store: store),
          ].indexed.map((p) {
            // As páginas escondidas não se redesenham a cada alteração.
            return TickerMode(enabled: p.$1 == _tab, child: p.$2);
          }).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          const ['Calendário', 'Tarefas', 'Eventos', 'Workspace'][_tab],
        ),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([store, store.syncStatus]),
            builder: (context, _) => _SyncIndicator(store: store),
          ),
          if (widget.onSignOut != null || updatesSupported)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'update' => _checkUpdates(),
                'backup' => _showBackups(),
                _ => _confirmSignOut(),
              },
              itemBuilder: (context) => [
                if (widget.userEmail != null)
                  PopupMenuItem(enabled: false, child: Text(widget.userEmail!)),
                if (updatesSupported) ...[
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      buildTime == null
                          ? 'Versão ${_version ?? '…'}'
                          : 'Versão ${_version ?? '…'}\n'
                                'criada a ${fmtBuildDate(buildTime!)}',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'update',
                    child: Text('Procurar atualizações'),
                  ),
                  const PopupMenuItem(
                    value: 'backup',
                    child: Text('Cópias de segurança'),
                  ),
                ],
                if (widget.onSignOut != null)
                  const PopupMenuItem(
                    value: 'out',
                    child: Text('Terminar sessão'),
                  ),
              ],
            ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: _goTab,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: Text('Calendário'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.check_circle_outline),
                      selectedIcon: Icon(Icons.check_circle),
                      label: Text('Tarefas'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.emoji_events_outlined),
                      selectedIcon: Icon(Icons.emoji_events),
                      label: Text('Eventos'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.article_outlined),
                      selectedIcon: Icon(Icons.article),
                      label: Text('Workspace'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _goTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Calendário',
                ),
                NavigationDestination(
                  icon: Icon(Icons.check_circle_outline),
                  selectedIcon: Icon(Icons.check_circle),
                  label: 'Tarefas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.emoji_events_outlined),
                  selectedIcon: Icon(Icons.emoji_events),
                  label: 'Eventos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.article_outlined),
                  selectedIcon: Icon(Icons.article),
                  label: 'Workspace',
                ),
              ],
            ),
      // No telemóvel, no calendário cria-se um evento tocando num dia.
      // O Workspace tem os seus próprios botões.
      floatingActionButton:
          _tab == 3 || (_tab == 0 && MediaQuery.sizeOf(context).width < 600)
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(const ['Evento', 'Tarefa', 'Evento', ''][_tab]),
            ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, tip, color) = switch (store.status) {
      SyncStatus.localOnly => (
        Icons.cloud_off_outlined,
        'Modo local: sem sincronização',
        scheme.outline,
      ),
      SyncStatus.syncing => (Icons.sync, 'A sincronizar…', scheme.primary),
      SyncStatus.synced => (
        Icons.cloud_done_outlined,
        'Sincronizado',
        scheme.primary,
      ),
      SyncStatus.error => (
        Icons.cloud_off,
        'Sem ligação: ${store.pendingChanges} alteração(ões) por enviar. '
            'Toca para tentar de novo.',
        scheme.error,
      ),
    };
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, color: color),
      onPressed: store.status == SyncStatus.localOnly ? null : store.sync,
    );
  }
}
