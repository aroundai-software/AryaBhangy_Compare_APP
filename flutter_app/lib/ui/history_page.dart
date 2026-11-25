import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/compare_models.dart';
import '../services/result_store.dart';
import '../state/compare_controller.dart';
import 'check_review.dart';
import 'jobs_result_table.dart';
import 'theme.dart';
import 'tracksheet_filters.dart';

enum _HistorySort {
  newestRun,
  oldestRun,
  compareFromNewest,
  branchAz,
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.controller,
    this.active = true,
    this.openRunId,
    this.openMark,
    this.openRunToken = 0,
  });

  final CompareController controller;
  final bool active;
  final String? openRunId;
  final String? openMark;
  final int openRunToken;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final ResultStore _store = ResultStore();
  final DateFormat _uiDate = DateFormat('dd-MM-yyyy');
  final DateFormat _uiDateTime = DateFormat('dd-MM-yyyy, h:mm a');
  final TextEditingController _searchController = TextEditingController();

  List<HistoryRunSummary> _all = const [];
  bool _loading = true;
  String? _error;
  String? _selectedId;
  CompareResultView? _detail;
  bool _detailLoading = false;
  String _detailMark = statusAdded;

  String _branchFilter = 'All';
  String _search = '';
  _HistorySort _sort = _HistorySort.newestRun;
  bool _tableView = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _reload();
  }

  void _onController() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openRunToken != oldWidget.openRunToken) {
      _openFromShell(widget.openRunId);
      return;
    }
    // Leaving History: drop heavy detail table so Compare stays smooth.
    if (!widget.active && oldWidget.active && _selectedId != null) {
      setState(() {
        _selectedId = null;
        _detail = null;
        _detailLoading = false;
      });
      return;
    }
    if (widget.active && !oldWidget.active && _selectedId == null) {
      _reload();
    }
  }

  Future<void> _openFromShell(String? id) async {
    await _reload();
    if (!mounted) {
      return;
    }
    if (id != null && id.isNotEmpty) {
      final match = _all.where((item) => item.id == id);
      if (match.isNotEmpty) {
        await _openRun(match.first, mark: widget.openMark);
        return;
      }
    }
    if (_all.isNotEmpty) {
      await _openRun(_all.first, mark: widget.openMark);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _store.listHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _all = list;
        _loading = false;
        if (_selectedId != null &&
            !list.any((item) => item.id == _selectedId)) {
          _selectedId = null;
          _detail = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  List<String> get _branchOptions {
    final names = <String>{'All'};
    for (final item in _all) {
      if (item.branch.isNotEmpty) {
        names.add(item.branch);
      }
    }
    final sorted = names.where((name) => name != 'All').toList()..sort();
    return ['All', ...sorted];
  }

  List<HistoryRunSummary> get _filtered {
    var items = _all.where((item) {
      if (_branchFilter != 'All' && item.branch != _branchFilter) {
        return false;
      }
      final q = _search.trim().toLowerCase();
      if (q.isNotEmpty) {
        final hay =
            '${item.company} ${item.branch} ${item.from} ${item.to} ${item.savedAt}'
                .toLowerCase();
        if (!hay.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    items.sort((a, b) {
      switch (_sort) {
        case _HistorySort.newestRun:
          return (b.savedAtTime ?? DateTime(1970))
              .compareTo(a.savedAtTime ?? DateTime(1970));
        case _HistorySort.oldestRun:
          return (a.savedAtTime ?? DateTime(1970))
              .compareTo(b.savedAtTime ?? DateTime(1970));
        case _HistorySort.compareFromNewest:
          return (b.fromDate ?? DateTime(1970))
              .compareTo(a.fromDate ?? DateTime(1970));
        case _HistorySort.branchAz:
          final byBranch = a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
          if (byBranch != 0) {
            return byBranch;
          }
          return (b.savedAtTime ?? DateTime(1970))
              .compareTo(a.savedAtTime ?? DateTime(1970));
      }
    });
    return items;
  }

  void _clearFilters() {
    setState(() {
      _branchFilter = 'All';
      _search = '';
      _searchController.clear();
      _sort = _HistorySort.newestRun;
    });
  }

  Future<void> _openRun(HistoryRunSummary summary, {String? mark}) async {
    setState(() {
      _selectedId = summary.id;
      _detailLoading = true;
      _detail = null;
    });
    final loaded = await _store.loadHistory(summary.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _detailLoading = false;
      _detail = loaded;
      if (loaded != null) {
        _detailMark = (mark != null && mark.isNotEmpty) ? mark : _preferredMark(loaded);
      }
    });
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

  Future<void> _deleteRun(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this run?'),
        content: const Text(
          'This removes the saved compare from this PC only. Tracksheet is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: tsRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    await _store.deleteHistory(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedId = null;
      _detail = null;
    });
    await _reload();
  }

  Future<void> _exportDetail() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export history Excel',
      fileName: 'Aryabhangy_history_export.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null || path.isEmpty) {
      return;
    }
    final normalized =
        path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
    widget.controller.saveExcelFromSnapshot(normalized, detail);
  }

  String _fmtSaved(HistoryRunSummary item) {
    final at = item.savedAtTime;
    if (at == null) {
      return item.savedAt.isEmpty ? '—' : item.savedAt;
    }
    return _uiDateTime.format(at.toLocal());
  }

  String _fmtRange(HistoryRunSummary item) {
    final from = item.fromDate;
    final to = DateTime.tryParse(item.to);
    if (from == null && to == null) {
      return '${item.from} – ${item.to}';
    }
    final left = from != null ? _uiDate.format(from) : item.from;
    final right = to != null ? _uiDate.format(to) : item.to;
    return '$left – $right';
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedId != null) {
      return _DetailView(
        loading: _detailLoading,
        detail: _detail,
        mark: _detailMark,
        onBack: () => setState(() {
          _selectedId = null;
          _detail = null;
        }),
        onSelectMark: (mark) => setState(() {
          _detailMark = mark;
        }),
        onExport: _exportDetail,
        canWrite: widget.controller.canWriteToPractice,
        writeAllCount: _detail == null
            ? 0
            : widget.controller.writeAllCount(_detail!.rows, runId: _selectedId),
        isWritten: (row) => widget.controller.wasWritten(row, runId: _selectedId),
        writeNote: widget.controller.writeStatus.isNotEmpty
            ? widget.controller.writeStatus
            : (!widget.controller.practiceSite || !widget.controller.allowPracticeSave)
                ? 'Turn on Allow saving on the Tracksheet in Settings before writing.'
                : '',
        onWriteAll: () {
          final detail = _detail;
          if (detail != null) {
            widget.controller.writeAll(detail.rows, runId: _selectedId);
          }
        },
        onWriteOne: (row) => widget.controller.writeOne(row, runId: _selectedId),
        onDelete: () {
          final id = _selectedId;
          if (id != null) {
            _deleteRun(id);
          }
        },
      );
    }

    final items = _filtered;
    return ColoredBox(
      color: tsBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compare history',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: tsInk,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Saved on this PC. Site not changed.',
                        style: TextStyle(color: tsMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _tableView = true),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _tableView ? tsGreen : tsWhite,
                    foregroundColor: _tableView ? tsWhite : tsInk,
                    side: BorderSide(color: _tableView ? tsGreen : tsLine),
                  ),
                  child: const Text('Table'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _tableView = false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _tableView ? tsWhite : tsGreen,
                    foregroundColor: _tableView ? tsInk : tsWhite,
                    side: BorderSide(color: _tableView ? tsLine : tsGreen),
                  ),
                  child: const Text('Cards'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _reload,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tsGreen,
                    side: const BorderSide(color: tsGreen),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FilterPanel(
              branch: _branchFilter,
              branches: _branchOptions,
              searchController: _searchController,
              sort: _sort,
              onBranch: (value) => setState(() => _branchFilter = value),
              onSearch: (value) => setState(() => _search = value),
              onSort: (value) => setState(() => _sort = value),
              onClear: _clearFilters,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: tsRed)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(
                          child: Text(
                            'No saved compares yet. Run compare on the Compare page.',
                            style: TextStyle(color: tsMuted, fontSize: 14),
                          ),
                        )
                      : _tableView
                          ? _HistoryTable(
                              items: items,
                              savedLabel: _fmtSaved,
                              rangeLabel: _fmtRange,
                              onOpen: _openRun,
                            )
                          : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _HistoryCard(
                              summary: item,
                              runLabel: _fmtSaved(item),
                              rangeLabel: _fmtRange(item),
                              onTap: () => _openRun(item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.branch,
    required this.branches,
    required this.searchController,
    required this.sort,
    required this.onBranch,
    required this.onSearch,
    required this.onSort,
    required this.onClear,
  });

  final String branch;
  final List<String> branches;
  final TextEditingController searchController;
  final _HistorySort sort;
  final ValueChanged<String> onBranch;
  final ValueChanged<String> onSearch;
  final ValueChanged<_HistorySort> onSort;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tsLine),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _Labeled(
            label: 'Branch',
            child: SizedBox(
              width: 160,
              child: InputDecorator(
                decoration: _fieldDecoration(),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: branches.contains(branch) ? branch : 'All',
                    items: branches
                        .map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onBranch(value);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          _Labeled(
            label: 'Search',
            child: SizedBox(
              width: 200,
              child: TextField(
                controller: searchController,
                decoration: _fieldDecoration().copyWith(
                  hintText: 'Company / branch / dates',
                ),
                onChanged: onSearch,
              ),
            ),
          ),
          _Labeled(
            label: 'Sort',
            child: SizedBox(
              width: 200,
              child: InputDecorator(
                decoration: _fieldDecoration(),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<_HistorySort>(
                    isExpanded: true,
                    isDense: true,
                    value: sort,
                    items: const [
                      DropdownMenuItem(
                        value: _HistorySort.newestRun,
                        child: Text('Newest run first'),
                      ),
                      DropdownMenuItem(
                        value: _HistorySort.oldestRun,
                        child: Text('Oldest run first'),
                      ),
                      DropdownMenuItem(
                        value: _HistorySort.compareFromNewest,
                        child: Text('Compare From (newest)'),
                      ),
                      DropdownMenuItem(
                        value: _HistorySort.branchAz,
                        child: Text('Branch A–Z'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onSort(value);
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration() {
  return const InputDecoration(
    isDense: true,
    filled: true,
    fillColor: tsWhite,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(
      borderSide: BorderSide(color: tsLine),
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: tsLine),
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: tsMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({
    required this.items,
    required this.savedLabel,
    required this.rangeLabel,
    required this.onOpen,
  });

  final List<HistoryRunSummary> items;
  final String Function(HistoryRunSummary item) savedLabel;
  final String Function(HistoryRunSummary item) rangeLabel;
  final ValueChanged<HistoryRunSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tsLine),
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: const WidgetStatePropertyAll(tsGreen),
            headingTextStyle: const TextStyle(
              color: tsWhite,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            columns: const [
              DataColumn(label: Text('Run date')),
              DataColumn(label: Text('Branch and company')),
              DataColumn(label: Text('Period')),
              DataColumn(label: Text('Added'), numeric: true),
              DataColumn(label: Text('Check manually'), numeric: true),
              DataColumn(label: Text('Removed'), numeric: true),
              DataColumn(label: Text('No change'), numeric: true),
              DataColumn(label: Text('Rows'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final item in items)
                DataRow(
                  onSelectChanged: (_) => onOpen(item),
                  cells: [
                    DataCell(Text(savedLabel(item))),
                    DataCell(
                      Text(
                        item.company.isEmpty
                            ? (item.branch.isEmpty ? '—' : item.branch)
                            : '${item.branch}  ·  ${item.company}',
                      ),
                    ),
                    DataCell(Text(rangeLabel(item))),
                    DataCell(Text('${item.added}')),
                    DataCell(Text('${item.check}')),
                    DataCell(Text('${item.removed}')),
                    DataCell(Text('${item.keep}')),
                    DataCell(Text('${item.rowCount}')),
                    DataCell(
                      TextButton(
                        onPressed: () => onOpen(item),
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.summary,
    required this.runLabel,
    required this.rangeLabel,
    required this.onTap,
  });

  final HistoryRunSummary summary;
  final String runLabel;
  final String rangeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tsWhite,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tsLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    runLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tsInk,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    summary.branch.isEmpty ? '—' : summary.branch,
                    style: const TextStyle(
                      color: tsGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Compare $rangeLabel',
                style: const TextStyle(color: tsMuted, fontSize: 13),
              ),
              if (summary.company.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  summary.company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: tsInk, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _CountChip(label: statusAdded, value: summary.added, color: tsGreen),
                  _CountChip(label: statusRemoved, value: summary.removed, color: tsRed),
                  _CountChip(label: statusCheck, value: summary.check, color: tsAmber),
                  _CountChip(label: statusKeep, value: summary.keep, color: tsMuted),
                  _CountChip(
                    label: 'Rows',
                    value: summary.rowCount,
                    color: tsInk,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tsBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tsLine),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({
    required this.loading,
    required this.detail,
    required this.mark,
    required this.onBack,
    required this.onSelectMark,
    required this.onExport,
    required this.canWrite,
    required this.writeAllCount,
    required this.isWritten,
    required this.writeNote,
    required this.onWriteAll,
    required this.onWriteOne,
    required this.onDelete,
  });

  final bool loading;
  final CompareResultView? detail;
  final String mark;
  final VoidCallback onBack;
  final ValueChanged<String> onSelectMark;
  final VoidCallback onExport;
  final bool canWrite;
  final int writeAllCount;
  final bool Function(OutcomeRow row) isWritten;
  final String writeNote;
  final VoidCallback onWriteAll;
  final ValueChanged<OutcomeRow> onWriteOne;
  final VoidCallback onDelete;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  final TracksheetRowFilters _filters = TracksheetRowFilters();
  final TextEditingController _searchController = TextEditingController();
  Object? _boundDetail;
  String? _cachedMark;
  List<OutcomeRow> _markRows = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshMarkRows({bool clearFilters = false}) {
    if (clearFilters) {
      _filters.clear();
      _searchController.clear();
    }
    _boundDetail = widget.detail;
    _cachedMark = widget.mark;
    _markRows = widget.detail?.rows
            .where((row) => row.mark == widget.mark)
            .toList(growable: false) ??
        const <OutcomeRow>[];
  }

  @override
  void didUpdateWidget(covariant _DetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final detailChanged = !identical(widget.detail, _boundDetail);
    final markChanged = oldWidget.mark != widget.mark;
    if (detailChanged || markChanged) {
      _refreshMarkRows(clearFilters: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(widget.detail, _boundDetail) ||
        _cachedMark != widget.mark) {
      _refreshMarkRows();
    }
    final markRows = _markRows;
    final rows = _filters.apply(markRows);
    return ColoredBox(
      color: tsBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tsGreen,
                    side: const BorderSide(color: tsGreen),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back to list'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tsRed,
                    side: const BorderSide(color: tsRed),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete this run'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: widget.canWrite && widget.writeAllCount > 0
                      ? widget.onWriteAll
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: tsGreen,
                    foregroundColor: tsWhite,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text('Write all (${widget.writeAllCount})'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.detail == null ? null : widget.onExport,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tsGreen,
                    side: const BorderSide(color: tsGreen),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.table_view_outlined, size: 18),
                  label: const Text('Export Excel'),
                ),
                const Spacer(),
                if (widget.detail != null)
                  Text(
                    '${widget.detail!.branch}  ·  ${widget.detail!.from} → ${widget.detail!.to}',
                    style: const TextStyle(color: tsMuted, fontSize: 12),
                  ),
              ],
            ),
              if (widget.writeNote.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.writeNote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: tsMuted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
            if (widget.loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (widget.detail == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Could not load this run.',
                    style: TextStyle(color: tsRed),
                  ),
                ),
              )
            else ...[
              _DetailTabs(
                detail: widget.detail!,
                selected: widget.mark,
                onSelect: widget.onSelectMark,
              ),
              const SizedBox(height: 8),
              if (widget.mark == statusCheck)
                Expanded(
                  child: CheckWorkbench(
                    rows: markRows,
                    vouchers: widget.detail!.vouchers,
                    canWrite: widget.canWrite,
                    isWritten: widget.isWritten,
                    onWrite: widget.onWriteOne,
                  ),
                )
              else ...[
              TracksheetFilterBar(
                sourceRows: markRows,
                filters: _filters,
                searchController: _searchController,
                visibleCount: rows.length,
                onChanged: () {
                  if (mounted) {
                    setState(() {});
                  }
                },
                onExport: widget.onExport,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: JobsResultTable(
                  key: ValueKey(widget.mark),
                  rows: rows,
                  emptyLabel: markRows.isEmpty
                      ? 'No rows with this action status.'
                      : 'No rows match these filters.',
                  onWrite: widget.canWrite ? widget.onWriteOne : null,
                  isWritten: widget.isWritten,
                ),
              ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailTabs extends StatelessWidget {
  const _DetailTabs({
    required this.detail,
    required this.selected,
    required this.onSelect,
  });

  final CompareResultView detail;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, int)>[
      (statusAdded, detail.added),
      (statusRemoved, detail.removed),
      (statusCheck, detail.check),
      (statusKeep, detail.keep),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${tab.$1}  ${tab.$2}'),
                selected: selected == tab.$1,
                onSelected: (_) => onSelect(tab.$1),
                selectedColor: tsGreenSoft,
                labelStyle: TextStyle(
                  color: selected == tab.$1 ? tsGreen : tsInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected == tab.$1 ? tsGreen : tsLine,
                ),
                backgroundColor: tsWhite,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

