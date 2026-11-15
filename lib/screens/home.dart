// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'calendar.dart';
import 'event_edit.dart';
import 'events_page.dart';
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ao voltar à app, ir buscar o que mudou nos outros dispositivos.
    if (state == AppLifecycleState.resumed) store.sync();
  }

  /// Quantas vezes se entrou em Tarefas (a timeline volta a centrar hoje).
  int _taskVisits = 0;

  void _goTab(int i) => setState(() {
    if (i == 1 && _tab != 1) _taskVisits++;
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
      children: [
        CalendarPage(
          store: store,
          selectedDay: _selectedDay,
          onDaySelected: (d) => setState(() => _selectedDay = d),
        ),
        TasksPage(store: store, visit: _taskVisits),
        EventsPage(store: store),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(const ['Calendário', 'Tarefas', 'Eventos'][_tab]),
        actions: [
          ListenableBuilder(
            listenable: store,
            builder: (context, _) => _SyncIndicator(store: store),
          ),
          if (widget.onSignOut != null)
            PopupMenuButton<String>(
              onSelected: (_) => _confirmSignOut(),
              itemBuilder: (context) => [
                if (widget.userEmail != null)
                  PopupMenuItem(enabled: false, child: Text(widget.userEmail!)),
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
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(const ['Evento', 'Tarefa', 'Evento'][_tab]),
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
