import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Versões publicadas em "Releases" no GitHub (o workflow `build` cria uma
/// por compilação, com o instalador de Windows e o APK).
const _latestRelease =
    'https://api.github.com/repos/milheirobernardowork/calendario/releases/latest';

class UpdateCheck {
  const UpdateCheck({
    required this.installed,
    this.latest,
    this.download,
    this.error,
  });

  /// Versão instalada (ex.: "1.0.14").
  final String installed;

  /// Versão mais recente publicada, se se conseguiu saber.
  final String? latest;

  /// Ficheiro a descarregar para esta plataforma.
  final Uri? download;

  final String? error;

  bool get hasUpdate =>
      latest != null && compareVersions(latest!, installed) > 0;
}

/// Só faz sentido nas apps instaladas (não na versão web).
bool get updatesSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isWindows);

Future<String> installedVersion() async =>
    (await PackageInfo.fromPlatform()).version;

/// Compara "1.0.9" com "1.0.10" número a número.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp(r'[.+-]'))
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

Future<UpdateCheck> checkForUpdate() async {
  final installed = await installedVersion();
  try {
    final res = await http
        .get(
          Uri.parse(_latestRelease),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      return UpdateCheck(
        installed: installed,
        error: 'O GitHub respondeu ${res.statusCode}',
      );
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final latest = (json['tag_name'] as String).replaceFirst('v', '');
    final wanted = Platform.isAndroid ? 'WolfCal.apk' : 'WolfCal-Setup.exe';
    Uri? download;
    for (final a in (json['assets'] as List? ?? const [])) {
      final asset = a as Map<String, dynamic>;
      if (asset['name'] == wanted) {
        download = Uri.parse(asset['browser_download_url'] as String);
      }
    }
    download ??= Uri.parse(json['html_url'] as String);
    return UpdateCheck(
      installed: installed,
      latest: latest,
      download: download,
    );
  } catch (e) {
    return UpdateCheck(installed: installed, error: 'Sem ligação ao GitHub');
  }
}
