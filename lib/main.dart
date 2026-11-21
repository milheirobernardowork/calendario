// O pacote table_calendar e o flutter_localizations ainda assentam em
// package:flutter/material.dart, por isso usa-se o mesmo em toda a app.
// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backups.dart';
import 'config.dart';
import 'home_widget_sync.dart';
import 'localizations.dart';
import 'reminders.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'store.dart';
import 'supabase_sync.dart';

const appLocale = 'pt_PT';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(appLocale);
  final prefs = await SharedPreferences.getInstance();
  final store = Store(prefs);

  SupabaseClient? client;
  if (supabaseConfigured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    client = Supabase.instance.client;
    SupabaseSync(client, store);
  }
  runApp(AgendaApp(store: store, client: client));
  // Depois de a app aparecer, para não atrasar o arranque.
  unawaited(Reminders(store).init());
  HomeWidgetSync(store, prefs).init();
  Backups.instance = Backups(store, prefs)..init();
}

class AgendaApp extends StatelessWidget {
  const AgendaApp({super.key, required this.store, this.client});

  final Store store;

  /// `null` = modo local, sem conta nem sincronização.
  final SupabaseClient? client;

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3F6FD9),
      brightness: b,
    ),
    useMaterial3: true,
    // Título do seletor de data mais pequeno, para "domingo" caber inteiro.
    datePickerTheme: const DatePickerThemeData(
      headerHeadlineStyle: TextStyle(fontSize: 24),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WolfCal',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('pt', 'PT'),
      supportedLocales: const [Locale('pt', 'PT')],
      localizationsDelegates: const [
        // Antes das globais, para a semana começar à segunda-feira.
        PtPtMaterialLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: client == null
          ? HomeScreen(store: store)
          : _AuthGate(store: store, client: client!),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.store, required this.client});

  final Store store;
  final SupabaseClient client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, _) {
        if (client.auth.currentSession == null) {
          return LoginScreen(client: client);
        }
        return HomeScreen(
          store: store,
          userEmail: client.auth.currentUser?.email,
          onSignOut: () async {
            await client.auth.signOut();
            await store.clearLocal();
          },
        );
      },
    );
  }
}
