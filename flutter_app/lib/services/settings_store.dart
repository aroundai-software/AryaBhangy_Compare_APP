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
    this.voucherTypesByCompany = const <String, List<String>>{},
  });

  final String tallyPort;
  final String website;
  final bool allowPracticeSave;

  /// Saved voucher types keyed by the exact Tally company name.
  /// A missing company means the user has not saved a choice yet.
  final Map<String, List<String>> voucherTypesByCompany;

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
        voucherTypesByCompany: _voucherTypes(raw['voucherTypesByCompany']),
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
        'voucherTypesByCompany': settings.voucherTypesByCompany,
      }),
      flush: true,
    );
  }
}

Map<String, List<String>> _voucherTypes(Object? raw) {
  if (raw is! Map) {
    return const {};
  }
  final types = <String, List<String>>{};
  for (final entry in raw.entries) {
    final company = entry.key.toString().trim();
    if (company.isEmpty || entry.value is! List) {
      continue;
    }
    final names = <String>[];
    for (final item in entry.value as List) {
      final name = item.toString().trim();
      if (name.isNotEmpty && !names.contains(name)) {
        names.add(name);
      }
    }
    types[company] = names;
  }
  return types;
}
