import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../bridge/python_bridge.dart';
import '../models/compare_models.dart';
import '../ui/check_review.dart';
import '../services/result_store.dart';
import '../services/settings_store.dart';

const allBranches = 'All branches';

/// To date of the latest finished compare for this Tally company and branch.
String? latestToFor({
  required String company,
  required String branch,
  required List<HistoryRunSummary> runs,
  CompareResultView? pending,
}) {
  HistoryRunSummary? best;
  for (final run in runs) {
    if (!_sameText(run.company, company) || !_sameText(run.branch, branch)) {
      continue;
    }
    if (run.to.trim().isEmpty) {
      continue;
    }
    if (best == null || _savedAfter(run.savedAtTime, best.savedAtTime)) {
      best = run;
    }
  }
  var to = best?.to;
  var bestSaved = best?.savedAtTime;
  if (pending != null &&
      _sameText(pending.company, company) &&
      _sameText(pending.branch, branch) &&
      pending.to.trim().isNotEmpty) {
    final pendingSaved = DateTime.tryParse(pending.savedAt);
    if (pendingSaved == null || _savedAfter(pendingSaved, bestSaved)) {
      to = pending.to;
    }
  }
  final text = (to ?? '').trim();
  return text.isEmpty ? null : text;
}

bool _sameText(String left, String right) => left.trim() == right.trim();

bool _savedAfter(DateTime? candidate, DateTime? current) {
  if (candidate == null) {
    return false;
  }
  if (current == null) {
    return true;
  }
  return candidate.isAfter(current);
}

class CompareController extends ChangeNotifier {
  CompareController({PythonBridge? bridge, ResultStore? store, SettingsStore? settings})
      : _bridge = bridge ?? PythonBridge(),
        _store = store ?? ResultStore(),
        _settings = settings ?? SettingsStore();

  final PythonBridge _bridge;
  final ResultStore _store;
  final SettingsStore _settings;
  final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
  final DateFormat _uiDate = DateFormat('dd-MM-yyyy');

  bool starting = true;
  bool busy = false;
  bool tallyOnline = false;
  String company = '';
  String status = 'Starting…';
  String selectedDetail = '';
  String selectedMark = statusAdded;
  String selectedBranch = allBranches;
  List<String> branches = const [allBranches];
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  CompareResultView? result;
  String? lastHistoryRunId;
  String? lastError;
  String tallyPort = defaultTallyPort;
  String website = defaultWebsite;
  bool allowPracticeSave = false;
  bool checkingConnection = false;
  String connectionNote = '';
  bool writing = false;
  String writeStatus = '';
  String writtenFor = '';
  final Map<String, Set<String>> writtenByRun = {};

  bool get practiceSite {
    final host = Uri.tryParse(website.trim())?.host.toLowerCase() ?? '';
    return host == '127.0.0.1' || host == 'localhost';
  }

  List<OutcomeRow> get visibleRows {
    final current = result;
    if (current == null) {
      return const [];
    }
    return current.rows.where((row) => row.mark == selectedMark).toList();
  }

  Future<void> start() async {
    starting = true;
    lastError = null;
    notifyListeners();
    _bridge.onEvent = _handleEvent;
    _bridge.onLog = debugPrint;
    try {
      writtenByRun
        ..clear()
        ..addAll(await _store.loadWrittenKeys());
      final runs = await _store.listHistory();
      if (runs.isNotEmpty) {
        lastHistoryRunId = runs.first.id;
      }
      final saved = await _store.load();
      if (saved != null) {
        result = saved;
        _applyResultFilters(saved);
        selectedMark = _preferredMark(saved);
        status = 'Loaded last saved compare.';
      }
      final settings = await _settings.load();
      tallyPort = settings.tallyPort;
      website = settings.website;
      allowPracticeSave = settings.allowPracticeSave && practiceSite;
      await _bridge.start();
      if (_settingsProblem() == null) {
        _sendSettings();
      }
      _bridge.send(const {'cmd': 'ping'});
      _bridge.send(const {'cmd': 'branches.load'});
      if (result == null) {
        status = 'Ready. Open a company in Tally, then run compare.';
      }
    } catch (error) {
      lastError = '$error';
      status = 'Could not start the Python worker.';
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> disposeBridge() async {
    await _bridge.stop();
  }

  void setBranch(String? value) {
    if (value == null || value.isEmpty) {
      return;
    }
    selectedBranch = value;
    notifyListeners();
  }

  void setFrom(DateTime value) {
    fromDate = DateTime(value.year, value.month, value.day);
    if (toDate.isBefore(fromDate)) {
      toDate = fromDate;
    }
    notifyListeners();
  }

  void setTo(DateTime value) {
    toDate = DateTime(value.year, value.month, value.day);
    if (toDate.isBefore(fromDate)) {
      fromDate = toDate;
    }
    notifyListeners();
  }

  void setConnectionFields(String port, String site) {
    tallyPort = port.trim();
    website = site.trim();
    if (!practiceSite) {
      allowPracticeSave = false;
    }
    notifyListeners();
    if (_settingsProblem() == null) {
      _persistSettings();
    }
  }

  void setAllowPracticeSave(bool value) {
    allowPracticeSave = value && practiceSite;
    notifyListeners();
    _persistSettings();
    _sendSettings();
  }

  void checkConnection() {
    final problem = _settingsProblem();
    if (problem != null) {
      connectionNote = problem;
      notifyListeners();
      return;
    }
    checkingConnection = true;
    connectionNote = '';
    notifyListeners();
    _sendSettings(check: true);
  }

  String? _settingsProblem() {
    final port = int.tryParse(tallyPort.trim());
    if (port == null || port < 1 || port > 65535) {
      return 'Tally port must be from 1 to 65535.';
    }
    final uri = Uri.tryParse(website.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Enter a website address starting with http:// or https://.';
    }
    return null;
  }

  void _sendSettings({bool check = false}) {
    _bridge.send({
      'cmd': check ? 'settings.check' : 'settings.apply',
      'tally_port': tallyPort.trim(),
      'website': website.trim(),
      'allow_practice_save': allowPracticeSave && practiceSite,
    });
  }

  Future<void> _persistSettings() async {
    try {
      await _settings.save(
        AppSettings(
          tallyPort: tallyPort.trim().isEmpty ? defaultTallyPort : tallyPort.trim(),
          website: website.trim(),
          allowPracticeSave: allowPracticeSave && practiceSite,
        ),
      );
    } catch (error) {
      debugPrint('Could not save settings: $error');
    }
  }

  void selectMark(String mark) {
    selectedMark = mark;
    selectedDetail = '';
    notifyListeners();
  }

  void selectRow(OutcomeRow row) {
    selectedDetail = row.reason;
    notifyListeners();
  }

  bool get canWriteToPractice => practiceSite && allowPracticeSave && !writing && !busy;

  int writeAllCount(Iterable<OutcomeRow> rows, {String? runId}) =>
      rows.where((row) => _isPendingBulkRow(row, runId)).length;

  bool wasWritten(OutcomeRow row, {String? runId}) {
    final target = runId ?? lastHistoryRunId ?? 'latest';
    return writtenByRun[target]?.contains(_writeKey(row)) ?? false;
  }

  void writeAll(Iterable<OutcomeRow> rows, {String? runId}) {
    _writeRows(
      rows.where((row) => _isPendingBulkRow(row, runId)).toList(),
      runId: runId,
      bulk: true,
    );
  }

  void writeOne(OutcomeRow row, {String? runId}) {
    if (row.jobCard.isEmpty) {
      lastError = 'That row has no job card to write.';
      writeStatus = lastError!;
      status = lastError!;
      notifyListeners();
      return;
    }
    if (!checkRowWriteEnabled(row.reason)) {
      lastError = 'JC ${row.jobCard} is not on the Tracksheet. Nothing was written.';
      writeStatus = lastError!;
      status = lastError!;
      notifyListeners();
      return;
    }
    _writeRows([row], runId: runId, bulk: false);
  }

  bool _isBulkRow(OutcomeRow row) =>
      row.jobCard.isNotEmpty && (row.mark == statusAdded || row.mark == statusKeep);

  bool _isPendingBulkRow(OutcomeRow row, String? runId) =>
      _isBulkRow(row) && !wasWritten(row, runId: runId);

  String _writeKey(OutcomeRow row) => '${row.jobCard}|${row.vehicle}';

  void _writeRows(List<OutcomeRow> rows, {String? runId, required bool bulk}) {
    if (busy || writing) {
      return;
    }
    if (!practiceSite) {
      lastError = 'Writing is only allowed on the Tracksheet on this computer.';
      writeStatus = lastError!;
      status = lastError!;
      notifyListeners();
      return;
    }
    if (!allowPracticeSave) {
      lastError = 'Turn on Allow saving on the Tracksheet in Settings.';
      writeStatus = lastError!;
      status = lastError!;
      notifyListeners();
      return;
    }
    if (rows.isEmpty) {
      lastError = bulk
          ? 'Nothing to write. Check manually stays off Write all.'
          : 'Choose a job card to write.';
      writeStatus = lastError!;
      status = lastError!;
      notifyListeners();
      return;
    }
    writing = true;
    writtenFor = runId ?? lastHistoryRunId ?? 'latest';
    lastError = null;
    writeStatus = bulk
        ? 'Writing ${rows.length} job cards to the Tracksheet…'
        : 'Writing JC ${rows.first.jobCard} to the Tracksheet…';
    status = bulk
        ? 'Writing ${rows.length} job cards to the Tracksheet…'
        : 'Writing JC ${rows.first.jobCard} to the Tracksheet…';
    notifyListeners();
    _bridge.send({
      'cmd': 'tracksheet.write',
      'website': website.trim(),
      'allow_practice_save': true,
      'rows': [
        for (final row in rows)
          {
            'key': _writeKey(row),
            'job_card': row.jobCard,
            'vehicle': row.vehicle,
            'reason': row.reason,
            'tally_bills': row.tallyBills,
            'bill': row.trackBill,
            'labour': row.labour,
            'spares': row.spares,
            'total': row.amount,
            'vas': row.vas,
            'items': row.items,
          },
      ],
    });
  }

  Future<void> syncFromLast() async {
    if (busy) {
      return;
    }
    if (!tallyOnline || company.isEmpty) {
      lastError =
          'Tally is offline, or no company is loaded. Open a company in Tally first.';
      status = lastError!;
      notifyListeners();
      return;
    }
    final branch = _syncBranch();
    if (branch == null) {
      lastError =
          'Choose the branch for this Tally company. Sync from last continues that branch only.';
      status = lastError!;
      notifyListeners();
      return;
    }
    final runs = await _store.listHistory();
    final lastText = latestToFor(
      company: company,
      branch: branch,
      runs: runs,
      pending: result,
    );
    final last = lastText == null ? null : DateTime.tryParse(lastText);
    if (last == null) {
      lastError =
          'Run a compare with dates first for $branch. Sync from last continues the day after that.';
      status = lastError!;
      notifyListeners();
      return;
    }
    final lastDay = DateTime(last.year, last.month, last.day);
    final start = lastDay.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (start.isAfter(today)) {
      lastError = 'Nothing new for $branch since ${formatDate(lastDay)}.';
      status = lastError!;
      notifyListeners();
      return;
    }
    selectedBranch = branch;
    fromDate = start;
    toDate = today;
    runCompare();
  }

  String? _syncBranch() {
    if (selectedBranch != allBranches) {
      return selectedBranch;
    }
    final folded = company.toLowerCase();
    String? matched;
    for (final name in branches) {
      if (name == allBranches) {
        continue;
      }
      if (folded.contains(name.toLowerCase())) {
        if (matched == null || name.length > matched.length) {
          matched = name;
        }
      }
    }
    return matched;
  }

  void runCompare() {
    if (busy) {
      return;
    }
    if (!tallyOnline || company.isEmpty) {
      lastError =
          'Tally is offline, or no company is loaded. Open a company in Tally first.';
      notifyListeners();
      return;
    }
    final problem = _settingsProblem();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return;
    }
    _sendSettings();
    busy = true;
    result = null;
    selectedDetail = '';
    lastError = null;
    lastHistoryRunId = null;
    writtenFor = '';
    writeStatus = '';
    status = 'Reading Tracksheet and Tally…';
    notifyListeners();
    _bridge.send({
      'cmd': 'compare.run',
      'from': _apiDate.format(fromDate),
      'to': _apiDate.format(toDate),
      'branch': selectedBranch,
    });
  }

  void saveExcel(String path) {
    if (result == null) {
      lastError = 'Run compare before exporting Excel.';
      notifyListeners();
      return;
    }
    status = 'Writing Excel…';
    notifyListeners();
    _bridge.send({'cmd': 'report.save', 'path': path});
  }

  void saveExcelFromSnapshot(String path, CompareResultView snapshot) {
    status = 'Writing Excel…';
    lastError = null;
    notifyListeners();
    _bridge.send({
      'cmd': 'report.save',
      'path': path,
      'snapshot': snapshot.toJson(),
    });
  }

  String formatDate(DateTime value) => _uiDate.format(value);

  void _handleEvent(Map<String, dynamic> event) {
    final kind = (event['event'] ?? '').toString();
    switch (kind) {
      case 'pong':
        if (result == null) {
          status = 'Ready.';
        }
        break;
      case 'tally.status':
        tallyOnline = event['online'] == true;
        company = (event['company'] ?? '').toString();
        if (!tallyOnline) {
          status = 'Tally offline';
        } else if (company.isEmpty) {
          status = 'Tally online — no company loaded';
        } else {
          status = 'Tally online — $company';
          _preferCompanyBranch(company);
        }
        break;
      case 'branches.loaded':
        final names = <String>[allBranches];
        final raw = event['names'];
        if (raw is List) {
          for (final item in raw) {
            final text = item.toString();
            if (text.isNotEmpty && !names.contains(text)) {
              names.add(text);
            }
          }
        }
        branches = names;
        final preferred = (event['preferred'] ?? '').toString();
        if (preferred.isNotEmpty && names.contains(preferred)) {
          selectedBranch = preferred;
        } else if (!names.contains(selectedBranch)) {
          selectedBranch = allBranches;
        }
        _preferCompanyBranch(company);
        break;
      case 'progress':
        final source = (event['source'] ?? '').toString();
        final label = (event['label'] ?? event['day'] ?? '').toString();
        final count = event['count'] ?? 0;
        final elapsed = event['elapsed_s'];
        final clock = elapsed == null ? '' : ' · ${elapsed}s';
        status = 'Reading $source · $label · $count$clock';
        break;
      case 'compare.result':
        busy = false;
        final view = CompareResultView.fromJson(event);
        result = view;
        _applyResultFilters(view);
        selectedMark = _preferredMark(view);
        final timing = event['timing'];
        var timingNote = '';
        if (timing is Map) {
          final total = timing['total_s'];
          final track = timing['tracksheet_s'];
          final tally = timing['tally_s'];
          final jc = timing['extra_jc_s'];
          final cmp = timing['compare_s'];
          timingNote =
              ' Time ${total}s (Tracksheet ${track}s · Tally ${tally}s · '
              'Extra JC ${jc}s · Match ${cmp}s).';
        }
        status =
            '$statusAdded ${view.added} · '
            '$statusRemoved ${view.removed} · $statusCheck ${view.check} · '
            '$statusKeep ${view.keep} · Vouchers ${view.voucherRows}. '
            'The Tracksheet is not changed until you write.'
            '$timingNote';
        _persist(view);
        break;
      case 'report.saved':
        status = 'Excel saved: ${event['path']}';
        break;
      case 'tracksheet.written':
        writing = false;
        final written = event['written'];
        if (written is List) {
          final keys = writtenByRun.putIfAbsent(writtenFor, () => <String>{});
          for (final item in written) {
            final key = item.toString();
            if (key.isNotEmpty) {
              keys.add(key);
            }
          }
          if (writtenFor.isNotEmpty && writtenFor != 'latest') {
            _store.saveWrittenKeys(writtenFor, keys);
          }
        }
        final failed = event['failed'];
        final failedCount = failed is List ? failed.length : 0;
        final updated = event['updated'] ?? 0;
        if (failedCount == 0) {
          lastError = null;
          writeStatus = 'Wrote $updated job card row(s) on the Tracksheet.';
          status = writeStatus;
        } else {
          var detail = '';
          if (failed is List && failed.isNotEmpty && failed.first is Map) {
            final first = failed.first as Map;
            detail = '${first['job_card'] ?? ''} ${first['error'] ?? ''}'.trim();
          }
          lastError = 'Wrote $updated. $failedCount could not be written. $detail'.trim();
          writeStatus = lastError!;
          status = writeStatus;
        }
        break;
      case 'settings.checked':
        checkingConnection = false;
        final tallyMessage = (event['tally_message'] ?? '').toString();
        final websiteMessage = (event['website_message'] ?? '').toString();
        connectionNote = '$tallyMessage\n$websiteMessage';
        break;
      case 'error':
        busy = false;
        final wasWriting = writing;
        writing = false;
        checkingConnection = false;
        lastError = (event['message'] ?? 'Unknown error').toString();
        status = lastError!;
        if (wasWriting) {
          writeStatus = lastError!;
        }
        break;
      case 'shutdown':
        status = 'Worker stopped';
        break;
    }
    notifyListeners();
  }

  Future<void> _persist(CompareResultView view) async {
    try {
      await _store.save(view);
      lastHistoryRunId = await _store.saveHistory(view);
      if (writtenFor == 'latest' && lastHistoryRunId != null) {
        final pending = writtenByRun.remove('latest');
        writtenFor = lastHistoryRunId!;
        if (pending != null && pending.isNotEmpty) {
          writtenByRun[writtenFor] = pending;
          await _store.saveWrittenKeys(writtenFor, pending);
        }
      }
      final stamped = await _store.load();
      if (stamped != null) {
        result = stamped;
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Could not save compare result: $error');
    }
  }

  void _applyResultFilters(CompareResultView view) {
    if (view.branches.isNotEmpty) {
      branches = view.branches;
    }
    if (view.branch.isNotEmpty && branches.contains(view.branch)) {
      selectedBranch = view.branch;
    }
    final parsedFrom = DateTime.tryParse(view.from);
    final parsedTo = DateTime.tryParse(view.to);
    if (parsedFrom != null) {
      fromDate = DateTime(parsedFrom.year, parsedFrom.month, parsedFrom.day);
    }
    if (parsedTo != null) {
      toDate = DateTime(parsedTo.year, parsedTo.month, parsedTo.day);
    }
  }

  String _preferredMark(CompareResultView view) {
    if (view.added > 0) {
      return statusAdded;
    }
    if (view.removed > 0) {
      return statusRemoved;
    }
    if (view.check > 0) {
      return statusCheck;
    }
    return statusKeep;
  }

  void _preferCompanyBranch(String companyName) {
    if (companyName.isEmpty || selectedBranch != allBranches) {
      return;
    }
    final folded = companyName.toLowerCase();
    String? matched;
    for (final name in branches) {
      if (name == allBranches) {
        continue;
      }
      if (folded.contains(name.toLowerCase())) {
        if (matched == null || name.length > matched.length) {
          matched = name;
        }
      }
    }
    if (matched != null) {
      selectedBranch = matched;
    }
  }
}
