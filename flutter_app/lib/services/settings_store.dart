import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const defaultTallyPort = '9000';
const defaultWebsite = '';

class AppSettings {
  const AppSettings({
    required this.tallyPort,
    required this.website,
    required this.allowPracticeSave,
  });

  final String tallyPort;
  final String website;
  final bool allowPracticeSave;

  static const current = AppSettings(
    tallyPort: defaultTallyPort,
    website: defaultWebsite,
    allowPracticeSave: false,
  );
}

class SettingsStore {
  Future<File> _file() async {
    final appData = Platform.environment['APPDATA'];
    final root = (appData == null || appData.isEmpty)
        ? Directory.systemTemp.path
        : appData;
    final dir = Directory(p.join(root, 'AryabhangyCompare'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'settings.json'));
  }

  Future<AppSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return AppSettings.current;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) {
        return AppSettings.current;
      }
      final port = (raw['tallyPort'] ?? defaultTallyPort).toString().trim();
      final website = (raw['website'] ?? '').toString().trim();
      return AppSettings(
        tallyPort: port.isEmpty ? defaultTallyPort : port,
        website: website,
        allowPracticeSave: raw['allowPracticeSave'] == true,
      );
    } catch (_) {
      return AppSettings.current;
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'tallyPort': settings.tallyPort,
        'website': settings.website,
        'allowPracticeSave': settings.allowPracticeSave,
      }),
      flush: true,
    );
  }
}
