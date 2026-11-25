import 'package:flutter/material.dart';

import '../models/compare_models.dart';
import 'theme.dart';

const checkCauseAll = 'All';

const checkCauseOrder = <String>[
  'Total differs',
  'Bill number differs',
  'Vehicle number differs',
  'In Tally, not on the Tracksheet',
  'Service bill not assigned',
  'Same job card, two vehicles',
  'Duplicate on the Tracksheet',
  'Job Card incomplete',
  'Tally bill incomplete',
  'Other',
];

String checkCause(String reason) {
  final text = reason.toLowerCase();
  if (text.contains('totals differ')) {
    return 'Total differs';
  }
  if (text.contains('bill numbers differ')) {
    return 'Bill number differs';
  }
  if (text.contains('vehicle numbers do not match')) {
    return 'Vehicle number differs';
  }
  if (text.contains('not on the tracksheet') ||
      text.contains('not on the practice copy')) {
    return 'In Tally, not on the Tracksheet';
  }
  if (text.contains('was not added to a job') ||
      text.contains('could not be joined') ||
      text.contains('two hirise bills') ||
      text.contains('share this customer and date')) {
    return 'Service bill not assigned';
  }
  if (text.contains('different vehicles')) {
    return 'Same job card, two vehicles';
  }
  if (text.contains('more than once')) {
    return 'Duplicate on the Tracksheet';
  }
  if (text.contains('this tally bill') &&
      (text.contains('no job-card') ||
          text.contains('no job card') ||
          text.contains('no vehicle'))) {
    return 'Tally bill incomplete';
  }
  if (text.contains('missing on the tracksheet') ||
      text.contains('missing the job card') ||
      text.contains('has no vehicle number') ||
      text.contains('has no job card number') ||
      text.contains('no job card number and no vehicle number')) {
    return 'Job Card incomplete';
  }
  if (text.contains('no job-card') ||
      text.contains('no job card') ||
      text.contains('no vehicle')) {
    return 'Tally bill incomplete';
  }
  return 'Other';
}

/// Write can update a job card that is already on the Tracksheet.
/// A Tally bill with no Tracksheet row cannot be written.
bool checkRowWriteEnabled(String reason) =>
    checkCause(reason) != 'In Tally, not on the Tracksheet';

/// Shorter wording for remarks already saved with the old sentences.
String plainRemark(
  String reason, {
  String jobCard = '',
  String vehicle = '',
}) {
  final raw = reason.trim();
  if (raw.isEmpty) {
    return raw;
  }

  final date = RegExp(
    r'Job [Cc]ard date (.+?) differs from bill date (.+?)\.',
  ).firstMatch(raw);
  final dateLine = date == null
      ? ''
      : ' The job card date (${date.group(1)}) is different from the bill date (${date.group(2)}).';

  final add = RegExp(r'Add on Tracksheet: ([^\n]+)').firstMatch(raw);
  if (add != null) {
    var fill = add.group(1)!.trim();
    fill = fill.replaceAll(RegExp(r'\s*Figures shown are from Tally.*'), '');
    fill = fill.replaceAll(';', ',').trim();
    fill = fill.replaceAllMapped(
      RegExp(r'\b(Labour|Spares) ([0-9][0-9,]*(?:\.[0-9]+)?)'),
      (match) => '${match[1]} ₹${match[2]}',
    );
    return remarkLines(
      'Ready to fill: $fill.$dateLine Labour and spares are before GST. Nothing is written until you press Write.',
    );
  }

  if (raw.contains('was not added to a job')) {
    final service = RegExp(
      r'Service bill (.+?) on (.+?) for (.+?) was not added to a job\.',
    ).firstMatch(raw);
    if (service != null) {
      return 'Service bill ${service.group(1)} on ${service.group(2)} for ${service.group(3)} could not be joined to one job. There was no single Hirise bill for this vehicle on that day. Nothing was written.';
    }
  }

  if (raw.contains('not on the tracksheet')) {
    return 'This bill is in Tally, but it is not on the Tracksheet. Check it before adding a job card.';
  }

  if (raw.contains('missing on the tracksheet') ||
      raw.contains('missing the job card')) {
    return _blankFieldRemark(jobCard, vehicle, onTally: false);
  }

  if (raw.contains('no job-card number or no vehicle number') ||
      raw.contains('no job card number or no vehicle number')) {
    return _blankFieldRemark(jobCard, vehicle, onTally: true);
  }

  var text = raw.replaceAll(
    'Figures shown are from Tally and were not written to the Tracksheet. Labour and Spares are before GST. Total includes GST.',
    'Labour and spares are before GST. Nothing is written until you press Write.',
  );
  text = text.replaceAll(
    'Items column lists stock lines from the bill; full voucher also on Vouchers sheet.',
    '',
  );
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return remarkLines(text);
}

/// One sentence on each line. The GST note stays with the date sentence.
/// "Nothing is written until you press Write." stays on its own line.
String remarkLines(String text) {
  const gst = 'Labour and spares are before GST.';
  const write = 'Nothing is written until you press Write.';
  var body = text.replaceAll(
    RegExp(r'\s*The bill number on the Tracksheet is empty\.\s*'),
    ' ',
  );
  final hasGst = body.contains(gst);
  final hasWrite = body.contains(write);
  body = body.replaceAll(gst, ' ').replaceAll(write, ' ');
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (body.isEmpty && !hasGst && !hasWrite) {
    return '';
  }

  final parts = <String>[];
  final breaks = RegExp(r'\.\s+(?=[A-Z])');
  var start = 0;
  for (final match in breaks.allMatches(body)) {
    final sentence = body.substring(start, match.start + 1).trim();
    if (sentence.isNotEmpty) {
      parts.add(sentence);
    }
    start = match.end;
  }
  final tail = body.substring(start).trim();
  if (tail.isNotEmpty) {
    parts.add(tail.endsWith('.') ? tail : '$tail.');
  }

  if (hasGst && parts.isNotEmpty) {
    parts[parts.length - 1] = '${parts.last} $gst';
  } else if (hasGst) {
    parts.add(gst);
  }
  if (hasWrite) {
    parts.add(write);
  }
  return parts.join('\n');
}

(String, String)? vehicleMismatch(String reason) {
  final match = RegExp(
    r'on the Tracksheet for (.+?)\. The Tally bill is for (.+?)\.',
  ).firstMatch(reason);
  if (match == null) {
    return null;
  }
  return (match.group(1)!.trim(), match.group(2)!.trim());
}

String _blankFieldRemark(
  String jobCard,
  String vehicle, {
  required bool onTally,
}) {
  final jc = jobCard.trim();
  final reg = vehicle.trim();
  if (jc.isNotEmpty && reg.isEmpty) {
    return onTally
        ? 'Job Card $jc has no vehicle number on the Tally bill, so it could not be matched. Nothing was changed.'
        : 'Job Card $jc has no vehicle number. Nothing was changed.';
  }
  if (jc.isEmpty && reg.isNotEmpty) {
    return onTally
        ? 'The Tally bill for $reg has no job card number. Nothing was changed.'
        : 'Vehicle $reg has no job card number. Nothing was changed.';
  }
  return onTally
      ? 'This Tally bill has no job card number and no vehicle number. Nothing was changed.'
      : 'This row has no job card number and no vehicle number. Nothing was changed.';
}

class CheckCauseBar extends StatelessWidget {
  const CheckCauseBar({
    super.key,
    required this.rows,
    required this.selected,
    required this.onSelected,
  });

  final List<OutcomeRow> rows;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{for (final cause in checkCauseOrder) cause: 0};
    for (final row in rows) {
      final cause = checkCause(row.reason);
      counts[cause] = (counts[cause] ?? 0) + 1;
    }
    final chips = <(String, int)>[
      (checkCauseAll, rows.length),
      for (final cause in checkCauseOrder)
        if ((counts[cause] ?? 0) > 0) (cause, counts[cause]!),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${chip.$1}  ${chip.$2}'),
                selected: selected == chip.$1,
                onSelected: (_) => onSelected(chip.$1),
                selectedColor: tsCheckBg,
                backgroundColor: tsWhite,
                labelStyle: TextStyle(
                  color: selected == chip.$1 ? tsAmber : tsInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected == chip.$1 ? tsAmber : tsLine,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

class CheckComparePanel extends StatelessWidget {
  const CheckComparePanel({
    super.key,
    required this.row,
    required this.canWrite,
    required this.written,
    required this.onWrite,
  });

  final OutcomeRow row;
  final bool canWrite;
  final bool written;
  final VoidCallback? onWrite;

  @override
  Widget build(BuildContext context) {
    final title = [
      if (row.jobCard.isNotEmpty) row.jobCard,
      if (row.vehicle.isNotEmpty) row.vehicle,
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? 'Check manually' : title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tsInk,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                checkCause(row.reason),
                style: const TextStyle(
                  color: tsAmber,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              if (written)
                const Text(
                  'Saved',
                  style: TextStyle(
                    color: tsGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                )
              else if (canWrite &&
                  row.jobCard.isNotEmpty &&
                  onWrite != null &&
                  checkRowWriteEnabled(row.reason))
                TextButton(
                  onPressed: onWrite,
                  style: TextButton.styleFrom(
                    foregroundColor: tsGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Write this card'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Side(
                  title: 'Tracksheet',
                  lines: [
                    _Line('Job card', row.jobCard),
                    _Line('Vehicle', row.vehicle),
                    _Line('Customer', row.customer),
                    _Line('Date', row.when),
                    _Line('Bill #', row.trackBill),
                    _Line('Status', row.status),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Side(
                  title: 'Tally bill',
                  lines: [
                    _Line('Bill', row.tallyBills),
                    _Line('Labour', row.labour),
                    _Line('Spares', row.spares),
                    _Line('Total', row.amount),
                    _Line('VAS', row.vas),
                    _Line('Items', row.items),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row.reason.isEmpty
                ? 'No remark on this row.'
                : plainRemark(
                    row.reason,
                    jobCard: row.jobCard,
                    vehicle: row.vehicle,
                  ),
            style: const TextStyle(color: tsInk, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class CheckWorkbench extends StatefulWidget {
  const CheckWorkbench({
    super.key,
    required this.rows,
    required this.vouchers,
    required this.canWrite,
    required this.isWritten,
    required this.onWrite,
  });

  final List<OutcomeRow> rows;
  final List<VoucherRowView> vouchers;
  final bool canWrite;
  final bool Function(OutcomeRow row) isWritten;
  final ValueChanged<OutcomeRow>? onWrite;

  @override
  State<CheckWorkbench> createState() => _CheckWorkbenchState();
}

class _CheckWorkbenchState extends State<CheckWorkbench> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _selectedKey;
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _key(OutcomeRow row) =>
      '${row.jobCard}|${row.vehicle}|${row.tallyBills}|${row.reason}';

  List<OutcomeRow> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.rows;
    }
    return widget.rows.where((row) {
      final hay =
          '${row.jobCard} ${row.vehicle} ${row.customer} ${row.trackBill} ${row.tallyBills} ${row.adviser}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  OutcomeRow? _selected(List<OutcomeRow> visible) {
    if (visible.isEmpty) {
      return null;
    }
    for (final row in visible) {
      if (_key(row) == _selectedKey) {
        return row;
      }
    }
    return visible.first;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selected = _selected(visible);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: Container(
            decoration: BoxDecoration(
              color: tsWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tsLine),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search JC, vehicle, customer…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    children: [
                      for (final cause in checkCauseOrder)
                        _CauseGroup(
                          cause: cause,
                          rows: visible
                              .where((row) => checkCause(row.reason) == cause)
                              .toList(),
                          collapsed: _collapsed.contains(cause),
                          selectedKey: selected == null ? '' : _key(selected),
                          rowKey: _key,
                          isWritten: widget.isWritten,
                          onToggle: () => setState(() {
                            if (!_collapsed.add(cause)) {
                              _collapsed.remove(cause);
                            }
                          }),
                          onSelect: (row) => setState(() => _selectedKey = _key(row)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: tsWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tsLine),
            ),
            child: selected == null
                ? const Center(
                    child: Text(
                      'No check rows match this search.',
                      style: TextStyle(color: tsMuted),
                    ),
                  )
                : _Inspector(
                    row: selected,
                    vouchers: widget.vouchers,
                    written: widget.isWritten(selected),
                    canWrite: widget.canWrite && widget.onWrite != null,
                    onWrite: widget.onWrite == null
                        ? null
                        : () => widget.onWrite!(selected),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CauseGroup extends StatelessWidget {
  const _CauseGroup({
    required this.cause,
    required this.rows,
    required this.collapsed,
    required this.selectedKey,
    required this.rowKey,
    required this.isWritten,
    required this.onToggle,
    required this.onSelect,
  });

  final String cause;
  final List<OutcomeRow> rows;
  final bool collapsed;
  final String selectedKey;
  final String Function(OutcomeRow row) rowKey;
  final bool Function(OutcomeRow row) isWritten;
  final VoidCallback onToggle;
  final ValueChanged<OutcomeRow> onSelect;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16,
                    color: tsMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      cause,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tsInk,
                      ),
                    ),
                  ),
                  Text(
                    '${rows.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tsMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Material(
                  color: rowKey(row) == selectedKey ? tsGreenSoft : tsWhite,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onSelect(row),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: rowKey(row) == selectedKey ? tsGreen : tsLine,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  [
                                    if (row.jobCard.isNotEmpty) row.jobCard,
                                    if (row.vehicle.isNotEmpty) row.vehicle,
                                  ].join('  ·  ').ifEmpty('No job card'),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (isWritten(row))
                                const Text(
                                  'Written',
                                  style: TextStyle(
                                    color: tsGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          if (row.customer.isNotEmpty)
                            Text(
                              row.customer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: tsMuted, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.row,
    required this.vouchers,
    required this.written,
    required this.canWrite,
    required this.onWrite,
  });

  final OutcomeRow row;
  final List<VoucherRowView> vouchers;
  final bool written;
  final bool canWrite;
  final VoidCallback? onWrite;

  @override
  Widget build(BuildContext context) {
    final related = vouchers.where((voucher) {
      if (row.jobCard.isNotEmpty && voucher.jobCard == row.jobCard) {
        return true;
      }
      return row.vehicle.isNotEmpty &&
          voucher.registration.isNotEmpty &&
          voucher.registration == row.vehicle;
    }).toList();
    final items = row.items
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row.jobCard.isEmpty ? 'No job card' : 'JC ${row.jobCard}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: tsInk,
                    ),
                  ),
                  if (vehicleMismatch(row.reason) case (final sheet, final tally)) ...[
                    _Pill('Tracksheet $sheet'),
                    _Pill('Tally $tally'),
                  ] else if (row.vehicle.isNotEmpty)
                    _Pill(row.vehicle),
                  if (row.status.isNotEmpty) _Pill(row.status),
                  _Pill(checkCause(row.reason)),
                  if (written)
                    const _Pill('Written', filled: true),
                ],
              ),
              if (row.customer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    row.customer,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (row.model.isNotEmpty) 'Model: ${row.model}',
                    if (row.adviser.isNotEmpty) 'Adviser: ${row.adviser}',
                    if (row.technician.isNotEmpty) 'Tech: ${row.technician}',
                  ].join('   ·   '),
                  style: const TextStyle(color: tsMuted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tsCheckBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  row.reason.isEmpty
                      ? 'This row needs a manual check.'
                      : plainRemark(
                          row.reason,
                          jobCard: row.jobCard,
                          vehicle: row.vehicle,
                        ),
                  style: const TextStyle(fontSize: 13, height: 1.35, color: tsInk),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'TRACKSHEET AND TALLY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tsMuted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              _DiffTable(row: row, tallyDate: _billDate(row, related)),
              if (related.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'TALLY VOUCHERS (${related.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tsMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                for (final voucher in related)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tsBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tsLine),
                      ),
                      child: Text(
                        [
                          voucher.voucherNumber,
                          voucher.when,
                          if (voucher.labour.isNotEmpty) 'Labour ${voucher.labour}',
                          if (voucher.spares.isNotEmpty) 'Spares ${voucher.spares}',
                          if (voucher.vas.isNotEmpty) 'VAS ${voucher.vas}',
                          if (voucher.note.isNotEmpty) voucher.note,
                        ].where((part) => part.isNotEmpty).join('   ·   '),
                        style: const TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ),
              ],
              if (items.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'ITEMS (${items.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tsMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                for (final item in items)
                  Text(item, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: tsLine)),
          ),
          child: Row(
            children: [
              if (written)
                const Text(
                  'Written on the Tracksheet',
                  style: TextStyle(color: tsGreen, fontWeight: FontWeight.w700),
                )
              else if (canWrite &&
                  row.jobCard.isNotEmpty &&
                  checkRowWriteEnabled(row.reason))
                FilledButton.icon(
                  onPressed: onWrite,
                  style: FilledButton.styleFrom(
                    backgroundColor: tsGreen,
                    foregroundColor: tsWhite,
                  ),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Write Tally values to Tracksheet'),
                )
              else
                const Text(
                  'This row stays on Check manually.',
                  style: TextStyle(color: tsMuted, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _billDate(OutcomeRow row, List<VoucherRowView> related) {
  if (row.tallyWhen.trim().isNotEmpty) {
    return row.tallyWhen;
  }
  final dates = <String>[];
  for (final voucher in related) {
    final when = voucher.when.trim();
    if (when.isNotEmpty && !dates.contains(when)) {
      dates.add(when);
    }
  }
  return dates.join(' and ');
}

class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.row, required this.tallyDate});

  final OutcomeRow row;
  final String tallyDate;

  @override
  Widget build(BuildContext context) {
    final lines = <(String, String, String)>[
      if (vehicleMismatch(row.reason) case (final sheet, final tally))
        ('Vehicle', sheet, tally),
      ('Bill #', _dash(_sheetBill()), _dash(row.tallyBills)),
      ('Date', _dash(_sheetDate()), _dash(tallyDate)),
      ('Labour', _dash(_sheetMoney(row.sheetLabour)), _dash(_tallyMoney(row.tallyLabour, row.labour))),
      ('Spares', _dash(_sheetMoney(row.sheetSpares)), _dash(_tallyMoney(row.tallySpares, row.spares))),
      ('Total', _dash(_sheetMoney(row.sheetTotal)), _dash(_tallyMoney(row.tallyTotal, row.amount))),
      ('VAS', _dash(_sheetMoney(row.sheetVas)), _dash(_tallyMoney(row.tallyVas, row.vas))),
    ];
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(88),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      border: TableBorder.all(color: tsLine),
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFF8FAF9)),
          children: [
            _Cell('Field', head: true),
            _Cell('Tracksheet', head: true),
            _Cell('Tally', head: true),
          ],
        ),
        for (final line in lines)
          TableRow(
            children: [
              _Cell(line.$1),
              _Cell(line.$2),
              _Cell(line.$3),
            ],
          ),
      ],
    );
  }

  String _sheetBill() => row.sheetKnown ? row.sheetBill : row.trackBill;

  String _sheetDate() => row.sheetKnown ? row.sheetWhen : row.when;

  String _sheetMoney(String value) => row.sheetKnown ? value : '';

  String _tallyMoney(String tallyValue, String fallback) =>
      row.sheetKnown ? tallyValue : fallback;

  String _dash(String value) => value.trim().isEmpty ? '—' : value;
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.head = false});

  final String text;
  final bool head;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: head ? FontWeight.w700 : FontWeight.w500,
          color: head ? tsMuted : tsInk,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? tsGreenSoft : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: filled ? tsGreen : tsLine),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: filled ? tsGreen : tsInk,
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

class _Line {
  const _Line(this.label, this.value);
  final String label;
  final String value;
}

class _Side extends StatelessWidget {
  const _Side({required this.title, required this.lines});

  final String title;
  final List<_Line> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tsBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: tsGreen,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${line.label}: ',
                      style: const TextStyle(
                        color: tsMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: line.value.trim().isEmpty ? '—' : line.value,
                      style: const TextStyle(color: tsInk, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
