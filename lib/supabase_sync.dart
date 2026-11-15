import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'store.dart';

class SupabaseRemote implements Remote {
  SupabaseRemote(this.client);

  final SupabaseClient client;
  static const _page = 1000;

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table) async {
    final all = <Map<String, dynamic>>[];
    for (var from = 0; ; from += _page) {
      final rows = await client
          .from(table)
          .select()
          .order('id')
          .range(from, from + _page - 1);
      all.addAll(rows);
      if (rows.length < _page) return all;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSince(
    String table,
    DateTime since,
  ) async {
    final all = <Map<String, dynamic>>[];
    for (var from = 0; ; from += _page) {
      final rows = await client
          .from(table)
          .select()
          .gt('updated_at', since.toUtc().toIso8601String())
          .order('id')
          .range(from, from + _page - 1);
      all.addAll(rows);
      if (rows.length < _page) return all;
    }
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    final uid = client.auth.currentUser!.id;
    await client.from(table).upsert([
      for (final r in rows) {...r, 'user_id': uid},
    ]);
  }

  @override
  Future<void> purge(String table, DateTime before) async {
    await client
        .from(table)
        .delete()
        .lt('deleted_at', before.toIso8601String());
  }
}

/// Liga a [Store] ao Supabase: segue o estado da sessão, ouve alterações em
/// tempo real e sincroniza periodicamente como rede de segurança.
class SupabaseSync {
  SupabaseSync(this.client, this.store) {
    _authSub = client.auth.onAuthStateChange.listen((data) {
      _apply(data.session);
    });
    _apply(client.auth.currentSession);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => store.sync());
  }

  final SupabaseClient client;
  final Store store;

  late final StreamSubscription<AuthState> _authSub;
  late final Timer _timer;
  RealtimeChannel? _channel;
  Timer? _debounce;
  String? _userId;

  void _apply(Session? session) {
    final uid = session?.user.id;
    if (uid == _userId) return;
    _userId = uid;
    final old = _channel;
    _channel = null;
    if (old != null) client.removeChannel(old);

    if (uid == null) {
      store.remote = null;
      return;
    }
    store.remote = SupabaseRemote(client);
    var channel = client.channel('agenda-$uid');
    for (final table in const ['events', 'tasks', 'categories']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _changed(),
      );
    }
    _channel = channel..subscribe();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), store.sync);
  }

  void dispose() {
    _authSub.cancel();
    _timer.cancel();
    _debounce?.cancel();
    final c = _channel;
    if (c != null) client.removeChannel(c);
  }
}
