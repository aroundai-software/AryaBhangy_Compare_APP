import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/compare_models.dart';

const _maxHistoryRuns = 100;

class HistoryRunSummary {
  const HistoryRunSummary({
    required this.id,
    required this.savedAt,
    required this.company,
    required this.branch,
    required this.from,
    required this.to,
    required this.added,
    required this.removed,
    required this.check,
    required this.keep,
    required this.rowCount,
  });

  final String id;
  final String savedAt;
  final String company;
  final String branch;
  final String from;
  final String to;
  final int added;
  final int removed;
  final int check;
  final int keep;
  final int rowCount;

  DateTime? get savedAtTime => DateTime.tryParse(savedAt);
  DateTime? get fromDate => DateTime.tryParse(from);
}

class ResultStore {
  Future<Directory> _rootDir() async {
    final appData = Platform.environment['APPDATA'];
    final root = (appData == null || appData.isEmpty)
        ? Directory.systemTemp.path
        : appData;
    final dir = Directory(p.join(root, 'AryabhangyCompare'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _historyDir() async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, 'history'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _lastFile() async {
    final root = await _rootDir();
    return File(p.join(root.path, 'last_compare.json'));
  }

  Future<File> _writtenFile() async {
    final root = await _rootDir();
    return File(p.join(root.path, 'written_keys.json'));
  }

  /// Job-card keys already written, kept per history run.
  Future<Map<String, Set<String>>> loadWrittenKeys() async {
    try {
      final file = await _writtenFile();
      if (!await file.exists()) {
        return {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return {};
      }
      final loaded = <String, Set<String>>{};
      decoded.forEach((id, value) {
        if (value is! List) {
          return;
        }
        final keys = value.map((item) => item.toString()).where((item) => item.isNotEmpty).toSet();
        if (keys.isNotEmpty) {
          loaded[id.toString()] = keys;
        }
      });
      return loaded;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveWrittenKeys(String runId, Set<String> keys) async {
    if (runId.trim().isEmpty) {
      return;
    }
    final all = await loadWrittenKeys();
    all[runId] = Set<String>.from(keys);
    await _writeWrittenKeys(all);
  }

  Future<void> forgetWrittenKeys(String runId) async {
    final all = await loadWrittenKeys();
    if (all.remove(runId) == null) {
      return;
    }
    await _writeWrittenKeys(all);
  }

  Future<void> _writeWrittenKeys(Map<String, Set<String>> all) async {
    final file = await _writtenFile();
    final payload = {
      for (final entry in all.entries) entry.key: entry.value.toList()..sort(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  Future<void> save(CompareResultView result) async {
    final file = await _lastFile();
    final stamped = result.copyWith(savedAt: DateTime.now().toIso8601String());
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(stamped.toJson()),
      flush: true,
    );
  }

  Future<CompareResultView?> load() async {
    try {
      final file = await _lastFile();
      if (!await file.exists()) {
        return null;
      }
      final text = await file.readAsString();
      if (text.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return null;
      }
      return CompareResultView.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Saves a new history run (always append). Returns the run id.
  Future<String> saveHistory(CompareResultView result) async {
    final now = DateTime.now().toUtc();
    final id =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}_'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final stamped = result.copyWith(savedAt: now.toIso8601String());
    final dir = await _historyDir();
    final file = File(p.join(dir.path, '$id.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(stamped.toJson()),
      flush: true,
    );
    await pruneHistory(_maxHistoryRuns);
    return id;
  }

  Future<List<HistoryRunSummary>> listHistory() async {
    final dir = await _historyDir();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final summaries = <HistoryRunSummary>[];
    for (final file in files) {
      try {
        final text = await file.readAsString();
        final decoded = jsonDecode(text);
        if (decoded is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(decoded);
        final id = p.basenameWithoutExtension(file.path);
        final rows = map['rows'];
        final rowCount = rows is List ? rows.length : 0;
        summaries.add(
          HistoryRunSummary(
            id: id,
            savedAt: (map['saved_at'] ?? '').toString(),
            company: (map['company'] ?? '').toString(),
            branch: (map['branch'] ?? '').toString(),
            from: (map['from'] ?? '').toString(),
            to: (map['to'] ?? '').toString(),
            added: _asInt(map['added']),
            removed: _asInt(map['removed']),
            check: _asInt(map['check']),
            keep: map.containsKey('keep')
                ? _asInt(map['keep'])
                : 0,
            rowCount: rowCount,
          ),
        );
      } catch (_) {
        // Skip corrupt files.
      }
    }
    summaries.sort((a, b) {
      final at = a.savedAtTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.savedAtTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return summaries;
  }

  Future<CompareResultView?> loadHistory(String id) async {
    try {
      final dir = await _historyDir();
      final file = File(p.join(dir.path, '$id.json'));
      if (!await file.exists()) {
        return null;
      }
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return null;
      }
      return CompareResultView.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteHistory(String id) async {
    final dir = await _historyDir();
    final file = File(p.join(dir.path, '$id.json'));
    if (await file.exists()) {
      await file.delete();
    }
    await forgetWrittenKeys(id);
  }

  Future<void> pruneHistory(int keep) async {
    final dir = await _historyDir();
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    if (files.length <= keep) {
      return;
    }
    for (final file in files.skip(keep)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value') ?? 0;
}
