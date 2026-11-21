import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart';

/// Cópias de segurança locais: um ficheiro JSON com eventos, tarefas,
/// colunas e páginas, a cada 12 horas enquanto a app está aberta (e ao abrir,
/// se a última tiver mais de 12 horas). Guardam-se as 14 mais recentes.
class Backups {
  Backups(this.store, this.prefs);

  /// A instância da app (criada no arranque).
  static Backups? instance;

  final Store store;
  final SharedPreferences prefs;
  Timer? _timer;

  static const every = Duration(hours: 12);
  static const keep = 14;
  static const _lastKey = 'last_backup';

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  DateTime? get lastBackup {
    final raw = prefs.getString(_lastKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  void init() {
    if (!supported) return;
    unawaited(_maybeBackup());
    // Verifica de hora a hora se já passaram 12 horas.
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _maybeBackup());
  }

  void dispose() => _timer?.cancel();

  Future<void> _maybeBackup() async {
    final last = lastBackup;
    if (last == null || DateTime.now().difference(last) >= every) {
      try {
        await backupNow();
      } catch (e) {
        debugPrint('Cópia de segurança falhou: $e');
      }
    }
  }

  /// Pasta das cópias: Documentos\WolfCal\Copias no Windows; no Android, a
  /// pasta da app (Android/data/…/files/Copias).
  Future<Directory> folder() async {
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    final dir = Directory(
      Platform.isWindows
          ? '${base.path}${sep}WolfCal${sep}Copias'
          : '${base.path}${sep}Copias',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Cópias existentes, da mais recente para a mais antiga.
  Future<List<File>> list() async {
    final dir = await folder();
    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<File> backupNow() async {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name =
        'wolfcal-${now.year}-${two(now.month)}-${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.json';
    final dir = await folder();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(jsonEncode(store.exportData()));
    await prefs.setString(_lastKey, now.toIso8601String());
    // Apagar as mais antigas.
    final all = await list();
    for (final old in all.skip(keep)) {
      await old.delete();
    }
    return file;
  }

  /// Repõe os dados de uma cópia (e envia-os para o servidor).
  Future<void> restore(File file) async {
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    store.importData(data);
  }
}
