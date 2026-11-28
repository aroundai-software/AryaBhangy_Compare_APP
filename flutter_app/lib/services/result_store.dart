import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
    _rememberSummary(dir, _summaryFields(
      id: id,
      savedAt: stamped.savedAt,
      company: stamped.company,
      branch: stamped.branch,
      from: stamped.from,
      to: stamped.to,
      added: stamped.added,
      removed: stamped.removed,
      check: stamped.check,
      keep: stamped.keep,
      rowCount: stamped.rows.length,
    ));
    await pruneHistory(_maxHistoryRuns);
    return id;
  }

  Future<List<HistoryRunSummary>> listHistory() async {
    final dir = await _historyDir();
    final raw = await Isolate.run(() => _loadHistorySummaries(dir.path));
    final summaries = raw.map(_summaryFromScan).toList();
    summaries.sort((a, b) {
      final at = a.savedAtTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.savedAtTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return summaries;
  }

  Future<CompareResultView?> loadHistory(String id) async {
    final bytes = await loadHistoryBytes(id);
    if (bytes == null) {
      return null;
    }
    return compareViewFromBytes(bytes);
  }

  /// File bytes only. The parsed view stays on the caller so a page glide
  /// is not frozen by copying every row back onto the UI isolate.
  Future<Uint8List?> loadHistoryBytes(String id) async {
    try {
      final dir = await _historyDir();
      return await Isolate.run(() => _readHistoryBytes(p.join(dir.path, '$id.json')));
    } catch (_) {
      return null;
    }
  }

  CompareResultView? compareViewFromBytes(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
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
    _forgetSummary(dir, id);
    await forgetWrittenKeys(id);
  }

  Future<void> pruneHistory(int keep) async {
    final dir = await _historyDir();
    final files = await dir
        .list()
        .where((entity) => entity is File && _isRunFile(entity.path))
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
    _dropMissingSummaries(dir);
  }
}

HistoryRunSummary _summaryFromScan(Map<String, Object?> map) {
  return HistoryRunSummary(
    id: (map['id'] ?? '').toString(),
    savedAt: (map['savedAt'] ?? '').toString(),
    company: (map['company'] ?? '').toString(),
    branch: (map['branch'] ?? '').toString(),
    from: (map['from'] ?? '').toString(),
    to: (map['to'] ?? '').toString(),
    added: _asInt(map['added']),
    removed: _asInt(map['removed']),
    check: _asInt(map['check']),
    keep: _asInt(map['keep']),
    rowCount: _asInt(map['rowCount']),
  );
}

const _historyIndexName = 'index.json';

bool _isRunFile(String path) {
  final name = p.basename(path);
  return name.endsWith('.json') && name != _historyIndexName;
}

Map<String, Object?> _summaryFields({
  required String id,
  required String savedAt,
  required String company,
  required String branch,
  required String from,
  required String to,
  required int added,
  required int removed,
  required int check,
  required int keep,
  required int rowCount,
}) {
  return {
    'id': id,
    'savedAt': savedAt,
    'company': company,
    'branch': branch,
    'from': from,
    'to': to,
    'added': added,
    'removed': removed,
    'check': check,
    'keep': keep,
    'rowCount': rowCount,
  };
}

void _rememberSummary(Directory dir, Map<String, Object?> summary) {
  final index = File(p.join(dir.path, _historyIndexName));
  final items = _readIndexItems(index);
  final id = summary['id'];
  items.removeWhere((item) => item['id'] == id);
  items.insert(0, summary);
  index.writeAsStringSync(jsonEncode(items));
}

void _forgetSummary(Directory dir, String id) {
  final index = File(p.join(dir.path, _historyIndexName));
  if (!index.existsSync()) {
    return;
  }
  final items = _readIndexItems(index)..removeWhere((item) => item['id'] == id);
  index.writeAsStringSync(jsonEncode(items));
}

void _dropMissingSummaries(Directory dir) {
  final index = File(p.join(dir.path, _historyIndexName));
  if (!index.existsSync()) {
    return;
  }
  final items = _readIndexItems(index).where((item) {
    final id = item['id'];
    return id is String && File(p.join(dir.path, '$id.json')).existsSync();
  }).toList();
  index.writeAsStringSync(jsonEncode(items));
}

List<Map<String, Object?>> _readIndexItems(File index) {
  if (!index.existsSync()) {
    return [];
  }
  try {
    final decoded = jsonDecode(index.readAsStringSync());
    if (decoded is! List) {
      return [];
    }
    return [
      for (final item in decoded)
        if (item is Map) Map<String, Object?>.from(item),
    ];
  } catch (_) {
    return [];
  }
}

/// Uses the small index. Full run files are read only when that index is missing.
List<Map<String, Object?>> _loadHistorySummaries(String directoryPath) {
  final dir = Directory(directoryPath);
  if (!dir.existsSync()) {
    return const [];
  }
  final runIds = <String>{};
  for (final entity in dir.listSync()) {
    if (entity is File && _isRunFile(entity.path)) {
      runIds.add(p.basenameWithoutExtension(entity.path));
    }
  }
  final index = File(p.join(directoryPath, _historyIndexName));
  final indexed = _readIndexItems(index);
  final indexedIds = <String>{
    for (final item in indexed)
      if (item['id'] is String) item['id']! as String,
  };
  if (indexed.isNotEmpty &&
      indexedIds.length == indexed.length &&
      indexedIds.length == runIds.length &&
      indexedIds.containsAll(runIds)) {
    return indexed;
  }
  final summaries = _scanHistorySummaries(directoryPath);
  try {
    index.writeAsStringSync(jsonEncode(summaries));
  } catch (_) {}
  return summaries;
}

/// Reads compare files off the UI isolate. Only the small summary crosses back.
List<Map<String, Object?>> _scanHistorySummaries(String directoryPath) {
  final dir = Directory(directoryPath);
  if (!dir.existsSync()) {
    return const [];
  }
  final summaries = <Map<String, Object?>>[];
  for (final entity in dir.listSync()) {
    if (entity is! File || !_isRunFile(entity.path)) {
      continue;
    }
    try {
      final decoded = jsonDecode(entity.readAsStringSync());
      if (decoded is! Map) {
        continue;
      }
      final rows = decoded['rows'];
      summaries.add(_summaryFields(
        id: p.basenameWithoutExtension(entity.path),
        savedAt: (decoded['saved_at'] ?? '').toString(),
        company: (decoded['company'] ?? '').toString(),
        branch: (decoded['branch'] ?? '').toString(),
        from: (decoded['from'] ?? '').toString(),
        to: (decoded['to'] ?? '').toString(),
        added: _asInt(decoded['added']),
        removed: _asInt(decoded['removed']),
        check: _asInt(decoded['check']),
        keep: decoded.containsKey('keep') ? _asInt(decoded['keep']) : 0,
        rowCount: rows is List ? rows.length : 0,
      ));
    } catch (_) {
      // Skip corrupt files.
    }
  }
  return summaries;
}

Uint8List? _readHistoryBytes(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  try {
    return file.readAsBytesSync();
  } catch (_) {
    return null;
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value') ?? 0;
}
