import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
    this.settled = true,
    this.motion = false,
    this.openRunId,
    this.openMark,
    this.openRunToken = 0,
    this.onHome,
  });

  final CompareController controller;
  final bool active;
  final bool settled;
  final bool motion;
  final String? openRunId;
  final String? openMark;
  final int openRunToken;
  final VoidCallback? onHome;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  final ResultStore _store = ResultStore();
  final DateFormat _uiDate = DateFormat('dd-MM-yyyy');
  final DateFormat _uiDateTime = DateFormat('dd-MM-yyyy, h:mm a');
  final TextEditingController _searchController = TextEditingController();

  List<HistoryRunSummary> _all = const [];
  List<HistoryRunSummary>? _deferredList;
  int _reloadSerial = 0;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _selectedId;
  CompareResultView? _detail;
  bool _detailLoading = false;
  String _detailMark = statusAdded;

  String _branchFilter = 'All';
  String _search = '';
  _HistorySort _sort = _HistorySort.newestRun;
  bool _tableView = true;
  int _openSerial = 0;
  CompareResultView? _queuedDetail;
  Uint8List? _queuedBytes;
  String? _queuedMark;
  bool _detailQueued = false;
  bool _flushPosted = false;
  int _previewAdded = 0;
  int _previewRemoved = 0;
  int _previewCheck = 0;
  int _previewKeep = 0;
  int _warmSerial = 0;
  bool _prepareDetail = false;
  final GlobalKey _listBoundary = GlobalKey();
  final GlobalKey _detailBoundary = GlobalKey();
  late final AnimationController _pane;
  late final CurvedAnimation _paneSlide;

  @override
  void initState() {
    super.initState();
    _pane = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _paneSlide = CurvedAnimation(
      parent: _pane,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeOutQuart,
    );
    _pane.addStatusListener(_onPaneStatus);
    widget.controller.addListener(_onController);
    _reload();
    _scheduleWarm();
  }

  void _onController() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleWarm();
  }

  /// Draws the latest run while the user is still on Compare, so a card click
  /// only has to slide a page that is already built.
  void _scheduleWarm() {
    final result = widget.controller.result;
    final id = widget.controller.lastHistoryRunId;
    if (result == null || id == null || id.isEmpty) {
      return;
    }
    if (widget.settled || widget.motion) {
      return;
    }
    final mark = result.added > 0 ? statusAdded : _preferredMark(result);
    if (_detail == result && _selectedId == id && _detailMark == mark && _pane.value == 1) {
      return;
    }
    final serial = ++_warmSerial;
    SchedulerBinding.instance.scheduleTask(() {
      if (!mounted || serial != _warmSerial) {
        return;
      }
      if (widget.settled || widget.motion) {
        return;
      }
      if (widget.controller.result != result || widget.controller.lastHistoryRunId != id) {
        return;
      }
      _pane.value = 1;
      setState(() {
        _selectedId = id;
        _detail = result;
        _detailLoading = false;
        _detailQueued = false;
        _queuedDetail = null;
        _queuedBytes = null;
        _detailMark = mark;
        _previewAdded = result.added;
        _previewRemoved = result.removed;
        _previewCheck = result.check;
        _previewKeep = result.keep;
      });
    }, Priority.idle);
  }

  void _onPaneStatus(AnimationStatus status) {
    if ((status == AnimationStatus.completed || status == AnimationStatus.dismissed) &&
        mounted) {
      _flushDetail();
    }
    if (status == AnimationStatus.dismissed && mounted && _selectedId == null) {
      _releaseParkedDetail();
    }
  }

  void _releaseParkedDetail() {
    final serial = _openSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || serial != _openSerial || _selectedId != null || _pane.value > 0.001) {
        return;
      }
      if (_detail == null && !_detailLoading && !_prepareDetail) {
        return;
      }
      setState(() {
        _detail = null;
        _detailLoading = false;
        _prepareDetail = false;
        _detailQueued = false;
        _queuedDetail = null;
        _queuedBytes = null;
      });
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _pane.removeStatusListener(_onPaneStatus);
    _paneSlide.dispose();
    _pane.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      _scheduleWarm();
    }
    if (widget.openRunToken != oldWidget.openRunToken) {
      _deferredList = null;
      _openFromShell(widget.openRunId);
    } else if (widget.active && !oldWidget.active && widget.motion) {
      // History tab, not a card. The warmed job-card page stays off this slide.
      _pane.value = 0;
      _selectedId = null;
      _detail = null;
      _detailLoading = false;
      _detailQueued = false;
      _prepareDetail = false;
    } else if (!widget.motion && _deferredList != null) {
      final list = _deferredList!;
      _deferredList = null;
      _publishList(list);
    } else if (widget.settled && !oldWidget.settled && _selectedId == null) {
      _reload(quiet: true);
    }
    if (!widget.motion && !_pane.isAnimating) {
      _flushDetail();
    }
  }

  Future<void> _openFromShell(String? id) async {
    final mark = widget.openMark;
    if (id != null && id.isNotEmpty) {
      HistoryRunSummary? known;
      for (final item in _all) {
        if (item.id == id) {
          known = item;
          break;
        }
      }
      await _openRun(known ?? _placeholderRun(id), mark: mark, glide: !widget.motion);
      return;
    }
    if (_all.isEmpty) {
      await _reload(quiet: true);
      if (!mounted || _all.isEmpty) {
        return;
      }
    }
    await _openRun(_all.first, mark: mark, glide: !widget.motion);
  }

  HistoryRunSummary _placeholderRun(String id) {
    return HistoryRunSummary(
      id: id,
      savedAt: '',
      company: '',
      branch: '',
      from: '',
      to: '',
      added: 0,
      removed: 0,
      check: 0,
      keep: 0,
      rowCount: 0,
    );
  }

  Future<void> _reload({bool quiet = false}) async {
    final serial = ++_reloadSerial;
    _deferredList = null;
    if (!quiet && mounted) {
      if (_all.isEmpty && !_loading) {
        setState(() {
          _loading = true;
          _error = null;
        });
      } else if (_all.isNotEmpty && !_refreshing) {
        setState(() => _refreshing = true);
      }
    }
    try {
      final list = await _store.listHistory();
      if (!mounted || serial != _reloadSerial) {
        return;
      }
      if (widget.motion) {
        _deferredList = list;
        return;
      }
      _publishList(list);
    } catch (error) {
      if (!mounted || serial != _reloadSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = '$error';
      });
    }
  }

  void _publishList(List<HistoryRunSummary> list) {
    if (_sameRuns(list) && !_loading && _error == null) {
      if (_refreshing) {
        setState(() => _refreshing = false);
      }
      return;
    }
    setState(() {
      _all = list;
      _loading = false;
      _refreshing = false;
      _error = null;
      if (_selectedId != null && !list.any((item) => item.id == _selectedId)) {
        _selectedId = null;
        _detail = null;
      }
    });
  }

  bool _sameRuns(List<HistoryRunSummary> list) {
    if (list.length != _all.length) {
      return false;
    }
    for (var i = 0; i < list.length; i++) {
      final next = list[i];
      final current = _all[i];
      if (next.id != current.id ||
          next.savedAt != current.savedAt ||
          next.rowCount != current.rowCount ||
          next.added != current.added ||
          next.removed != current.removed ||
          next.check != current.check ||
          next.keep != current.keep ||
          next.branch != current.branch ||
          next.company != current.company ||
          next.from != current.from ||
          next.to != current.to) {
        return false;
      }
    }
    return true;
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

  CompareResultView? _memoryRun(String id) {
    final current = widget.controller.result;
    if (current == null || widget.controller.lastHistoryRunId != id) {
      return null;
    }
    return current;
  }

  Future<void> _openRun(HistoryRunSummary summary, {String? mark, bool glide = true}) async {
    final serial = ++_openSerial;
    final id = summary.id;
    final animate = glide && !widget.motion;
    final cached = _memoryRun(id);
    final resolvedMark = (mark != null && mark.isNotEmpty)
        ? mark
        : (cached != null ? _preferredMark(cached) : _detailMark);
    if (cached != null &&
        _detail == cached &&
        _selectedId == id &&
        _detailMark == resolvedMark &&
        _pane.value == 1 &&
        !_detailLoading) {
      return;
    }
    if (cached == null) {
      setState(() {
        _selectedId = id;
        _detail = null;
        _detailLoading = false;
        _prepareDetail = false;
        _queuedDetail = null;
        _queuedBytes = null;
        _queuedMark = mark;
        _detailQueued = false;
        _previewAdded = summary.added;
        _previewRemoved = summary.removed;
        _previewCheck = summary.check;
        _previewKeep = summary.keep;
        if (mark != null && mark.isNotEmpty) {
          _detailMark = mark;
        }
      });
      final bytes = await _store.loadHistoryBytes(id);
      if (!mounted || serial != _openSerial || _selectedId != id) {
        return;
      }
      final loaded = bytes == null ? null : _store.compareViewFromBytes(bytes);
      if (!mounted || serial != _openSerial || _selectedId != id) {
        return;
      }
      setState(() {
        _detail = loaded;
        _detailLoading = false;
        _prepareDetail = true;
        if (loaded != null && (mark == null || mark.isEmpty)) {
          _detailMark = _preferredMark(loaded);
        }
      });
    } else {
      setState(() {
        _selectedId = id;
        _detail = cached;
        _detailLoading = false;
        _prepareDetail = true;
        _queuedDetail = null;
        _queuedBytes = null;
        _queuedMark = mark;
        _detailQueued = false;
        _detailMark = resolvedMark;
        _previewAdded = cached.added;
        _previewRemoved = cached.removed;
        _previewCheck = cached.check;
        _previewKeep = cached.keep;
      });
    }
    await _revealDetail(serial, id, animate);
  }

  Future<void> _revealDetail(int serial, String id, bool animate) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || serial != _openSerial || _selectedId != id) {
      return;
    }
    if (!animate) {
      _pane.value = 1;
      return;
    }
    if (_pane.value < 1) {
      _pane.forward(from: _pane.value);
    }
  }

  void _flushDetail() {
    if (!_detailQueued || !mounted || _flushPosted) {
      return;
    }
    if (_selectedId == null) {
      _detailQueued = false;
      return;
    }
    // A saved run is parsed only after the glide, so the slide itself stays light.
    if (widget.motion || _pane.isAnimating) {
      return;
    }
    _flushPosted = true;
    final serial = _openSerial;
    final id = _selectedId;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _flushPosted = false;
      if (!mounted || !_detailQueued || serial != _openSerial || _selectedId != id) {
        return;
      }
      if (widget.motion || _pane.isAnimating) {
        return;
      }
      final mark = _queuedMark;
      final ready = _queuedDetail;
      final bytes = _queuedBytes;
      _detailQueued = false;
      _queuedDetail = null;
      _queuedBytes = null;
      final loaded = ready ?? (bytes == null ? null : _store.compareViewFromBytes(bytes));
      if (!mounted || serial != _openSerial || _selectedId != id) {
        return;
      }
      setState(() {
        _detailLoading = false;
        _detail = loaded;
        if (loaded != null) {
          _detailMark = (mark != null && mark.isNotEmpty) ? mark : _preferredMark(loaded);
        }
      });
    });
  }

  void _backToList() {
    // Do not rebuild either page on the click. Both are already drawn.
    _selectedId = null;
    _prepareDetail = true;
    if (_pane.value == 0) {
      _releaseParkedDetail();
      return;
    }
    _pane.reverse();
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
            style: glassLook(fill: tsRed, foreground: tsWhite),
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
      _all = [for (final item in _all) if (item.id != id) item];
    });
    _backToList();
    await _reload(quiet: true);
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
    final list = RepaintBoundary(key: _listBoundary, child: _buildList());
    final wantsDetail = _selectedId != null || _detail != null || _detailLoading;
    if (!wantsDetail) {
      return list;
    }
    final detail = RepaintBoundary(key: _detailBoundary, child: _buildDetail());
    return AnimatedBuilder(
      animation: _paneSlide,
      builder: (context, _) {
        final t = _paneSlide.value;
        // Keep both pages mounted at rest, so Back only moves two finished pictures.
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FractionalTranslation(
                translation: Offset(-t, 0),
                transformHitTests: false,
                child: IgnorePointer(ignoring: t > 0.001, child: list),
              ),
              FractionalTranslation(
                translation: Offset(1 - t, 0),
                transformHitTests: false,
                child: IgnorePointer(ignoring: t < 0.999, child: detail),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetail() {
    return _DetailView(
        loading: _detailLoading,
        detail: _detail,
        previewAdded: _previewAdded,
        previewRemoved: _previewRemoved,
        previewCheck: _previewCheck,
        previewKeep: _previewKeep,
        mark: _detailMark,
        onBack: _backToList,
        onSelectMark: (mark) {
          _detailMark = mark;
        },
        onExport: _exportDetail,
        canWrite: widget.controller.canWriteToPractice,
        writeAllCount: _detail == null
            ? 0
            : widget.controller.writeAllCount(_detail!.rows, runId: _selectedId),
        isWritten: (row) => widget.controller.wasWritten(row, runId: _selectedId),
        writeNote: widget.controller.writeStatus.isNotEmpty
            ? widget.controller.writeStatus
            : widget.controller.writeBlockedNote,
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

  Widget _buildList() {
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
                if (widget.onHome != null) ...[
                  OutlinedButton.icon(
                    onPressed: widget.onHome,
                    style: glassLook(
                      foreground: tsGreen,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                ],
                const Expanded(
                  child: Text(
                    'Compare history',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: tsInk,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _tableView = true),
                  style: glassLook(
                    fill: _tableView ? tsGreen : glassQuietFill,
                    foreground: _tableView ? tsWhite : tsInk,
                  ),
                  child: const Text('Table'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _tableView = false),
                  style: glassLook(
                    fill: _tableView ? glassQuietFill : tsGreen,
                    foreground: _tableView ? tsInk : tsWhite,
                  ),
                  child: const Text('Cards'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (_loading || _refreshing) ? null : () => _reload(),
                  style: glassLook(foreground: tsGreen),
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

class _HistoryTable extends StatefulWidget {
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
  State<_HistoryTable> createState() => _HistoryTableState();
}

class _HistoryTableState extends State<_HistoryTable> {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tsLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: constraints.maxHeight,
                child: Scrollbar(
                  controller: _vertical,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _vertical,
                    primary: false,
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
                        for (final item in widget.items)
                          DataRow(
                            onSelectChanged: (_) => widget.onOpen(item),
                            cells: [
                              DataCell(Text(widget.savedLabel(item))),
                              DataCell(
                                Text(
                                  item.company.isEmpty
                                      ? (item.branch.isEmpty ? '—' : item.branch)
                                      : '${item.branch}  ·  ${item.company}',
                                ),
                              ),
                              DataCell(Text(widget.rangeLabel(item))),
                              DataCell(Text('${item.added}')),
                              DataCell(Text('${item.check}')),
                              DataCell(Text('${item.removed}')),
                              DataCell(Text('${item.keep}')),
                              DataCell(Text('${item.rowCount}')),
                              DataCell(
                                TextButton(
                                  onPressed: () => widget.onOpen(item),
                                  child: const Text('Open'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
    required this.previewAdded,
    required this.previewRemoved,
    required this.previewCheck,
    required this.previewKeep,
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
  final int previewAdded;
  final int previewRemoved;
  final int previewCheck;
  final int previewKeep;
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

class _DetailViewState extends State<_DetailView> with SingleTickerProviderStateMixin {
  static const List<String> _markOrder = [
    statusAdded,
    statusRemoved,
    statusCheck,
    statusKeep,
  ];

  final Map<String, TracksheetRowFilters> _filtersByMark = {};
  final Map<String, TextEditingController> _searchByMark = {};
  final Map<String, GlobalKey> _markBoundary = {};
  Object? _boundDetail;
  late String _shownMark;
  String? _incoming;
  int _markSerial = 0;
  bool _holdAtStart = false;
  late final AnimationController _markSlide;

  @override
  void initState() {
    super.initState();
    _boundDetail = widget.detail;
    _shownMark = widget.mark;
    _markSlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _markSlide.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishMarkSlide();
      }
    });
  }

  @override
  void dispose() {
    _markSlide.dispose();
    for (final search in _searchByMark.values) {
      search.dispose();
    }
    super.dispose();
  }

  TracksheetRowFilters _filtersFor(String mark) {
    return _filtersByMark.putIfAbsent(mark, TracksheetRowFilters.new);
  }

  TextEditingController _searchFor(String mark) {
    return _searchByMark.putIfAbsent(mark, TextEditingController.new);
  }

  GlobalKey _boundaryFor(String mark) {
    return _markBoundary.putIfAbsent(mark, GlobalKey.new);
  }

  int _markIndex(String mark) {
    final index = _markOrder.indexOf(mark);
    return index < 0 ? 0 : index;
  }

  List<OutcomeRow> _rowsFor(String mark) {
    final detail = widget.detail;
    if (detail == null) {
      return const [];
    }
    return [
      for (final row in detail.rows)
        if (row.mark == mark) row,
    ];
  }

  void _queueMark(String mark) {
    if (mark == _shownMark) {
      _incoming = null;
      _holdAtStart = false;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _shownMark = mark;
      _incoming = null;
      _holdAtStart = false;
      _filtersFor(mark).clear();
      _searchFor(mark).clear();
      return;
    }
    final serial = ++_markSerial;
    _incoming = mark;
    _holdAtStart = true;
    _filtersFor(mark).clear();
    _searchFor(mark).clear();
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted || serial != _markSerial || _incoming != mark) {
        return;
      }
      _holdAtStart = false;
      _markSlide.value = 0;
      _markSlide.forward();
    });
  }

  void _selectMark(String mark) {
    if (mark == (_incoming ?? _shownMark)) {
      return;
    }
    widget.onSelectMark(mark);
    _queueMark(mark);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _DetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final detailChanged = !identical(widget.detail, _boundDetail);
    if (detailChanged) {
      _boundDetail = widget.detail;
      _shownMark = widget.mark;
      _incoming = null;
      _holdAtStart = false;
      _markSerial++;
      for (final filters in _filtersByMark.values) {
        filters.clear();
      }
      for (final search in _searchByMark.values) {
        search.clear();
      }
      return;
    }
    if (widget.mark != _shownMark && widget.mark != _incoming) {
      _queueMark(widget.mark);
    }
  }

  void _finishMarkSlide() {
    final arrived = _incoming;
    if (arrived == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _incoming != arrived || _markSlide.status != AnimationStatus.completed) {
        return;
      }
      setState(() {
        _shownMark = arrived;
        _incoming = null;
        _holdAtStart = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final targetMark = _incoming ?? _shownMark;
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
                  style: glassLook(
                    foreground: tsGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back to list'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  style: glassLook(
                    foreground: tsRed,
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
                  style: glassLook(
                    fill: tsGreen,
                    foreground: tsWhite,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    widget.loading ? 'Write all' : 'Write all (${widget.writeAllCount})',
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: widget.detail == null ? null : widget.onExport,
                  style: glassLook(
                    foreground: tsGreen,
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
            _DetailTabs(
              added: widget.detail?.added ?? widget.previewAdded,
              removed: widget.detail?.removed ?? widget.previewRemoved,
              check: widget.detail?.check ?? widget.previewCheck,
              keep: widget.detail?.keep ?? widget.previewKeep,
              selected: targetMark,
              onSelect: _selectMark,
            ),
            const SizedBox(height: 8),
            if (widget.loading)
              const Expanded(child: SizedBox.expand())
            else if (widget.detail == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Could not load this run.',
                    style: TextStyle(color: tsRed),
                  ),
                ),
              )
            else
              Expanded(child: _slidingMarks()),
          ],
        ),
      ),
    );
  }

  Widget _slidingMarks() {
    final shown = _markPage(_shownMark);
    final incomingMark = _incoming;
    if (incomingMark == null) {
      return shown;
    }
    final incoming = _markPage(incomingMark);
    final dir = _markIndex(incomingMark) >= _markIndex(_shownMark) ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _markSlide,
      builder: (context, _) {
        final t = _holdAtStart ? 0.0 : Curves.easeOutQuart.transform(_markSlide.value);
        final moving = t > 0.001 && t < 0.999;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FractionalTranslation(
                translation: Offset(-dir * t, 0),
                transformHitTests: false,
                child: IgnorePointer(ignoring: moving || t > 0.001, child: shown),
              ),
              FractionalTranslation(
                translation: Offset(dir * (1 - t), 0),
                transformHitTests: false,
                child: IgnorePointer(ignoring: t < 0.999, child: incoming),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _markPage(String mark) {
    final markRows = _rowsFor(mark);
    if (mark == statusCheck) {
      return RepaintBoundary(
        key: _boundaryFor(mark),
        child: CheckWorkbench(
          rows: markRows,
          vouchers: widget.detail!.vouchers,
          canWrite: widget.canWrite,
          isWritten: widget.isWritten,
          onWrite: widget.onWriteOne,
        ),
      );
    }
    final filters = _filtersFor(mark);
    final rows = filters.apply(markRows);
    return RepaintBoundary(
      key: _boundaryFor(mark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TracksheetFilterBar(
            sourceRows: markRows,
            filters: filters,
            searchController: _searchFor(mark),
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
              rows: rows,
              emptyLabel: markRows.isEmpty
                  ? 'No rows with this action status.'
                  : 'No rows match these filters.',
              onWrite: widget.canWrite ? widget.onWriteOne : null,
              isWritten: widget.isWritten,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTabs extends StatelessWidget {
  const _DetailTabs({
    required this.added,
    required this.removed,
    required this.check,
    required this.keep,
    required this.selected,
    required this.onSelect,
  });

  final int added;
  final int removed;
  final int check;
  final int keep;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, int)>[
      (statusAdded, added),
      (statusRemoved, removed),
      (statusCheck, check),
      (statusKeep, keep),
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

