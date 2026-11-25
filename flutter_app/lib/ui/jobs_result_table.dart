import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/compare_models.dart';
import 'check_review.dart';
import 'copyable.dart';
import 'theme.dart';

/// Allows mouse / trackpad drag so the table can scroll sideways on Windows.
class _TableScrollBehavior extends MaterialScrollBehavior {
  const _TableScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Tracksheet-style Job Cards table with virtualized rows for smooth scrolling.
///
/// Left columns (# / JC / DATE / REG) stay fixed; the rest scroll horizontally
/// so shrinking the window never clips those identity columns.
class JobsResultTable extends StatefulWidget {
  const JobsResultTable({
    super.key,
    required this.rows,
    required this.emptyLabel,
    this.onSelect,
    this.onWrite,
    this.isWritten,
  });

  final List<OutcomeRow> rows;
  final String emptyLabel;
  final ValueChanged<OutcomeRow>? onSelect;
  final ValueChanged<OutcomeRow>? onWrite;
  final bool Function(OutcomeRow row)? isWritten;

  static const double rowHeight = 96;
  static const double headerHeight = 36;
  static const double itemsWidth = 360;
  static const double remarksWidth = 400;
  static const double vasWidth = 220;

  // Sticky identity columns (marked in the tracksheet UI).
  static const double colIndex = 40;
  static const double colJc = 72;
  static const double colDate = 90;
  static const double colReg = 110;
  static const double stickyColsWidth =
      colIndex + colJc + colDate + colReg; // 312
  static const double stickyPadLeft = 12;
  static const double stickyPadRight = 8;
  static const double stickyPaneWidth =
      stickyPadLeft + stickyColsWidth + stickyPadRight; // 332

  // Scrollable body columns (CUSTOMER … REMARKS).
  static const double scrollColsWidth = 140 +
      100 +
      130 +
      110 +
      100 +
      100 +
      90 +
      100 +
      vasWidth +
      itemsWidth +
      72 +
      72 +
      72 +
      80 +
      80 +
      remarksWidth; // 2226
  static const double scrollPadRight = 12;
  static const double scrollPaneWidth = scrollColsWidth + scrollPadRight;

  @override
  State<JobsResultTable> createState() => _JobsResultTableState();
}

class _JobsResultTableState extends State<JobsResultTable> {
  final _stickyVertical = ScrollController();
  final _scrollVertical = ScrollController();
  final _horizontal = ScrollController();
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    _stickyVertical.addListener(_onStickyScroll);
    _scrollVertical.addListener(_onScrollableScroll);
  }

  void _onStickyScroll() {
    _syncVertical(_stickyVertical, _scrollVertical);
  }

  void _onScrollableScroll() {
    _syncVertical(_scrollVertical, _stickyVertical);
  }

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) {
      return;
    }
    final next = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - next).abs() < 0.5) {
      return;
    }
    _syncingVertical = true;
    target.jumpTo(next);
    _syncingVertical = false;
  }

  @override
  void dispose() {
    _stickyVertical.removeListener(_onStickyScroll);
    _scrollVertical.removeListener(_onScrollableScroll);
    _stickyVertical.dispose();
    _scrollVertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JobsResultTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameRows(oldWidget.rows, widget.rows)) {
      if (_stickyVertical.hasClients) {
        _stickyVertical.jumpTo(0);
      }
      if (_scrollVertical.hasClients) {
        _scrollVertical.jumpTo(0);
      }
    }
  }

  bool _sameRows(List<OutcomeRow> previous, List<OutcomeRow> next) {
    if (identical(previous, next)) {
      return true;
    }
    if (previous.length != next.length) {
      return false;
    }
    for (var i = 0; i < previous.length; i++) {
      if (!identical(previous[i], next[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tsLine),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: widget.rows.isEmpty
            ? Center(
                child: Text(
                  widget.emptyLabel,
                  style: const TextStyle(color: tsMuted),
                ),
              )
            : ScrollConfiguration(
                behavior: const _TableScrollBehavior(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStickyPane(),
                    Expanded(child: _buildScrollablePane()),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStickyPane() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: tsWhite,
        border: Border(right: BorderSide(color: tsLine, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: SizedBox(
        width: JobsResultTable.stickyPaneWidth,
        child: Column(
          children: [
            const _StickyHeader(),
            Expanded(
              child: ListView.builder(
                controller: _stickyVertical,
                primary: false,
                itemExtent: JobsResultTable.rowHeight,
                itemCount: widget.rows.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                physics: const ClampingScrollPhysics(),
                itemBuilder: (context, index) {
                  final row = widget.rows[index];
                  return _StickyDataRow(
                    index: index + 1,
                    row: row,
                    onSelect: widget.onSelect,
                    onWrite: widget.onWrite,
                    written: widget.isWritten?.call(row) ?? false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollablePane() {
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      trackVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      notificationPredicate: (notification) =>
          notification.depth == 0 &&
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        primary: false,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: JobsResultTable.scrollPaneWidth,
          child: Column(
            children: [
              const _ScrollHeader(),
              Expanded(
                child: Scrollbar(
                  controller: _scrollVertical,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.depth == 0 &&
                      notification.metrics.axis == Axis.vertical,
                  child: ListView.builder(
                    controller: _scrollVertical,
                    primary: false,
                    itemExtent: JobsResultTable.rowHeight,
                    itemCount: widget.rows.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    physics: const ClampingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final row = widget.rows[index];
                      return _ScrollDataRow(
                        row: row,
                        onSelect: widget.onSelect,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: JobsResultTable.headerHeight,
      color: tsGreen,
      padding: const EdgeInsets.only(
        left: JobsResultTable.stickyPadLeft,
        right: JobsResultTable.stickyPadRight,
      ),
      child: const Row(
        children: [
          _H('#', JobsResultTable.colIndex),
          _H('JC', JobsResultTable.colJc),
          _H('DATE', JobsResultTable.colDate),
          _H('REG', JobsResultTable.colReg),
        ],
      ),
    );
  }
}

class _ScrollHeader extends StatelessWidget {
  const _ScrollHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: JobsResultTable.headerHeight,
      width: JobsResultTable.scrollPaneWidth,
      color: tsGreen,
      padding: const EdgeInsets.only(right: JobsResultTable.scrollPadRight),
      child: const Row(
        children: [
          _H('CUSTOMER', 140),
          _H('PHONE', 100),
          _H('MODEL', 130),
          _H('SERVICE', 110),
          _H('BOOKING', 100),
          _H('ADVISER', 100),
          _H('TECH', 90),
          _H('STATUS', 100),
          _H('VAS', JobsResultTable.vasWidth, tip: 'Service-bill name from Tally'),
          _H('ITEMS', JobsResultTable.itemsWidth),
          _H('BILL #', 72, tip: 'Last 4 digits of the Hirise bill'),
          _H('LABOUR', 72, tip: 'Before GST'),
          _H('SPARES', 72, tip: 'Before GST'),
          _H('PAY', 80),
          _H('TOTAL', 80, tip: 'With GST'),
          _H('REMARKS', JobsResultTable.remarksWidth),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.label, this.width, {this.tip});

  final String label;
  final double width;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final text = Copyable(
      child: Text(
        label,
        style: const TextStyle(
          color: tsWhite,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: tip == null ? text : Tooltip(message: tip, child: text),
    );
  }
}

Color _rowColor(String mark) {
  switch (mark) {
    case statusAdded:
      return tsAddedBg;
    case statusRemoved:
      return tsRemovedBg;
    case statusCheck:
      return tsCheckBg;
    default:
      return tsWhite;
  }
}

const _body = TextStyle(color: tsInk, fontSize: 12);
const _muted = TextStyle(color: tsMuted, fontSize: 12);

class _StickyDataRow extends StatelessWidget {
  const _StickyDataRow({
    required this.index,
    required this.row,
    this.onSelect,
    this.onWrite,
    this.written = false,
  });

  final int index;
  final OutcomeRow row;
  final ValueChanged<OutcomeRow>? onSelect;
  final ValueChanged<OutcomeRow>? onWrite;
  final bool written;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _rowColor(row.mark),
      child: InkWell(
        onTap: onSelect == null ? null : () => onSelect!(row),
        child: Container(
          height: JobsResultTable.rowHeight,
          padding: const EdgeInsets.only(
            left: JobsResultTable.stickyPadLeft,
            right: JobsResultTable.stickyPadRight,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: tsLine)),
          ),
          child: Row(
            children: [
              _C(
                width: JobsResultTable.colIndex,
                child: Copyable(child: Text('$index', style: _muted)),
              ),
              _C(
                width: JobsResultTable.colJc,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Copyable(
                      child: Text(
                        row.jobCard,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (onWrite != null && row.jobCard.isNotEmpty)
                      written
                          ? const Copyable(
                              child: Text(
                                'Saved',
                                style: TextStyle(
                                  color: tsGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : TextButton(
                              onPressed: () => onWrite!(row),
                              style: TextButton.styleFrom(
                                foregroundColor: tsGreen,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 22),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text(
                                'Write',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                  ],
                ),
              ),
              _C(
                width: JobsResultTable.colDate,
                child: Copyable(child: Text(row.when, style: _body)),
              ),
              _C(
                width: JobsResultTable.colReg,
                child: Copyable(child: Text(row.vehicle, style: _body)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollDataRow extends StatelessWidget {
  const _ScrollDataRow({
    required this.row,
    this.onSelect,
  });

  final OutcomeRow row;
  final ValueChanged<OutcomeRow>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _rowColor(row.mark),
      child: InkWell(
        onTap: onSelect == null ? null : () => onSelect!(row),
        child: Container(
          height: JobsResultTable.rowHeight,
          width: JobsResultTable.scrollPaneWidth,
          padding: const EdgeInsets.only(right: JobsResultTable.scrollPadRight),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: tsLine)),
          ),
          child: Row(
            children: [
              _C(
                width: 140,
                child: Copyable(
                  child: Text(row.customer, style: _body, maxLines: 2),
                ),
              ),
              _C(
                width: 100,
                child: Copyable(child: Text(row.phone, style: _body)),
              ),
              _C(
                width: 130,
                child: Copyable(
                  child: Text(row.model, style: _body, maxLines: 2),
                ),
              ),
              _C(
                width: 110,
                child: _Pill(text: row.service, tone: _PillTone.service),
              ),
              _C(
                width: 100,
                child: Copyable(child: Text(row.booking, style: _body)),
              ),
              _C(
                width: 100,
                child: Copyable(child: Text(row.adviser, style: _body)),
              ),
              _C(
                width: 90,
                child: Copyable(child: Text(row.technician, style: _body)),
              ),
              _C(
                width: 100,
                child: _Pill(text: row.status, tone: _PillTone.status),
              ),
              _C(width: JobsResultTable.vasWidth, child: _VasCell(text: row.vas)),
              _C(
                width: JobsResultTable.itemsWidth,
                child: _ItemsCell(text: row.items, jobCard: row.jobCard),
              ),
              _C(
                width: 72,
                child: Copyable(child: Text(row.trackBill, style: _body)),
              ),
              _C(
                width: 72,
                child: Copyable(child: Text(row.labour, style: _body)),
              ),
              _C(
                width: 72,
                child: Copyable(child: Text(row.spares, style: _body)),
              ),
              _C(
                width: 80,
                child: Copyable(child: Text(row.payment, style: _body)),
              ),
              _C(
                width: 80,
                child: Copyable(child: Text(row.amount, style: _body)),
              ),
              _C(
                width: JobsResultTable.remarksWidth,
                child: _RemarksCell(
                  text: plainRemark(
                    row.reason,
                    jobCard: row.jobCard,
                    vehicle: row.vehicle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _C extends StatelessWidget {
  const _C({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: child,
      ),
    );
  }
}

/// Full stock/VAS names that have no digits — must not be rejoined after `, `.
const _completeNoDigitItems = <String>{
  'CHAIN LUBRICATION',
  'CHAIN LUBE',
  'CHAINLUBE',
  'RSA',
  'AMC',
  'PAID SERVICE',
  'QUICK DC',
  'EXTENDED WARRANTY',
  'POLISH',
  'COATING',
  'CANVAS',
  'INJECTOR CLEAN',
  'FORK OIL CHANGE',
  'DECARBONISING',
};

bool _needsCommaRejoin(String fragment) {
  final folded = fragment.toUpperCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (folded.isEmpty) {
    return true;
  }
  if (_completeNoDigitItems.contains(folded)) {
    return false;
  }
  // No digit → unfinished name head (e.g. "RUBBER" before "MOUNT 90543…").
  return !RegExp(r'\d').hasMatch(folded);
}

List<String> _splitLegacyItemFullList(String text) {
  if (text.contains(';') && !text.contains(',')) {
    return text
        .split(RegExp(r';+'))
        .map((part) => part.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  final parts = text.split(RegExp(r',\s+'));
  if (parts.length <= 1) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? const <String>[] : <String>[cleaned];
  }

  final out = <String>[];
  var i = 0;
  while (i < parts.length) {
    var cur = parts[i].trim();
    while (i + 1 < parts.length && _needsCommaRejoin(cur)) {
      i += 1;
      final nxt = parts[i].trim();
      cur = cur.isEmpty ? nxt : '$cur, $nxt';
    }
    final cleaned = cur.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isNotEmpty) {
      out.add(cleaned);
    }
    i += 1;
  }
  return out;
}

/// Split ITEMS for display.
/// Prefer newlines (fresh compares). Legacy FullList uses `, ` with comma-name rejoin.
List<String> _itemLines(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  if (trimmed.contains('\n') || trimmed.contains('\r')) {
    return trimmed
        .split(RegExp(r'[\r\n]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }
  return _splitLegacyItemFullList(trimmed);
}

/// ITEMS cell with preview scroll; click opens a full expand dialog.
class _ItemsCell extends StatefulWidget {
  const _ItemsCell({required this.text, this.jobCard = ''});

  final String text;
  final String jobCard;

  @override
  State<_ItemsCell> createState() => _ItemsCellState();
}

class _ItemsCellState extends State<_ItemsCell> {
  final _vertical = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _openExpanded(List<String> lines) async {
    final jc = widget.jobCard.trim();
    final title = jc.isEmpty
        ? 'Items (${lines.length})'
        : 'Items · JC $jc (${lines.length})';
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: tsWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Copyable(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: tsInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18, color: tsMuted),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const Divider(height: 12, color: tsLine),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.separated(
                        itemCount: lines.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          return Copyable(
                            child: Text(
                              '${index + 1}. ${lines[index]}',
                              style: const TextStyle(
                                color: tsInk,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = _itemLines(widget.text);
    if (lines.isEmpty) {
      return const Copyable(
        child: Text('—', style: TextStyle(color: tsMuted, fontSize: 12)),
      );
    }

    const style = TextStyle(fontSize: 11, color: tsInk, height: 1.25);
    final countLabel = lines.length == 1 ? '1 item' : '${lines.length} items';
    // Absorb tap so the row InkWell does not fire; open expand view instead.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openExpanded(lines),
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: JobsResultTable.rowHeight - 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Copyable(
                    onTap: () => _openExpanded(lines),
                    child: Text(
                      countLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tsMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_full, size: 11, color: tsMuted),
                ],
              ),
              const SizedBox(height: 2),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) => true,
                  child: ScrollConfiguration(
                    behavior: const _TableScrollBehavior(),
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: lines.length > 2,
                      child: ListView.builder(
                        controller: _vertical,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Copyable(
                              onTap: () => _openExpanded(lines),
                              child: Text(
                                lines[index],
                                softWrap: true,
                                style: style,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// REMARKS cell: full text with its own vertical scrollbar (no ellipsis cut-off).
class _RemarksCell extends StatefulWidget {
  const _RemarksCell({required this.text});

  final String text;

  @override
  State<_RemarksCell> createState() => _RemarksCellState();
}

class _RemarksCellState extends State<_RemarksCell> {
  final _vertical = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.text.trim();
    if (raw.isEmpty) {
      return const Copyable(
        child: Text('—', style: TextStyle(color: tsMuted, fontSize: 12)),
      );
    }
    return SizedBox(
      height: JobsResultTable.rowHeight - 20,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: ScrollConfiguration(
          behavior: const _TableScrollBehavior(),
          child: Scrollbar(
            controller: _vertical,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              controller: _vertical,
              primary: false,
              child: Copyable(
                child: Text(
                  raw,
                  style: const TextStyle(
                    color: tsInk,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _PillTone { service, status, vas }

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.tone, this.wrap = false});

  final String text;
  final _PillTone tone;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = switch (tone) {
      _PillTone.service => (
          const Color(0xFFDBEAFE),
          const Color(0xFF1D4ED8),
        ),
      _PillTone.status => (
          const Color(0xFFE0F2FE),
          const Color(0xFF0369A1),
        ),
      _PillTone.vas => (
          const Color(0xFFDCFCE7),
          const Color(0xFF15803D),
        ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Copyable(
          child: Text(
            text,
            softWrap: wrap,
            maxLines: wrap ? null : 1,
            overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.$2,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _VasCell extends StatelessWidget {
  const _VasCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final names = text
        .split(RegExp(r'[,;|]'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final name in names)
          _Pill(text: name, tone: _PillTone.vas, wrap: true),
      ],
    );
  }
}
