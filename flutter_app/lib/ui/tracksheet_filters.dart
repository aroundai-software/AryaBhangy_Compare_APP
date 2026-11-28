import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/compare_models.dart';
import 'theme.dart';

const dateAll = 'All';
const dateToday = 'Today';
const dateYesterday = 'Yesterday';
const dateLast7 = 'Last 7 days';
const dateThisMonth = 'This month';
const dateCustom = 'Custom';

const _allBranches = 'All branches';
const _allServices = 'All service types';
const _allBookings = 'All booking sources';
const _allStatuses = 'All status';
const _allAdvisers = 'All advisers';

const _datePresets = [
  dateAll,
  dateToday,
  dateYesterday,
  dateLast7,
  dateThisMonth,
  dateCustom,
];

final _whenDateFormat = DateFormat('dd MMM yyyy');
final _shortDateFormat = DateFormat('dd-MM-yyyy');

class TracksheetRowFilters {
  String search = '';
  String datePreset = dateAll;
  DateTime? customFrom;
  DateTime? customTo;
  String branch = _allBranches;
  String service = _allServices;
  String booking = _allBookings;
  String status = _allStatuses;
  String adviser = _allAdvisers;

  void clear() {
    search = '';
    datePreset = dateAll;
    customFrom = null;
    customTo = null;
    branch = _allBranches;
    service = _allServices;
    booking = _allBookings;
    status = _allStatuses;
    adviser = _allAdvisers;
  }

  (DateTime?, DateTime?) dateRange({DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    switch (datePreset) {
      case dateToday:
        return (day, day);
      case dateYesterday:
        final y = day.subtract(const Duration(days: 1));
        return (y, y);
      case dateLast7:
        return (day.subtract(const Duration(days: 6)), day);
      case dateThisMonth:
        return (DateTime(day.year, day.month, 1), day);
      case dateCustom:
        return (customFrom, customTo);
      case dateAll:
      default:
        return (null, null);
    }
  }

  List<OutcomeRow> apply(List<OutcomeRow> rows) {
    final q = search.trim().toLowerCase();
    final range = dateRange();
    final start = range.$1;
    final end = range.$2;
    return rows.where((row) {
      if (!_rowMatchesDate(row.when, start, end)) {
        return false;
      }
      if (branch != _allBranches && row.branch != branch) {
        return false;
      }
      if (service != _allServices && row.service != service) {
        return false;
      }
      if (booking != _allBookings && row.booking != booking) {
        return false;
      }
      if (status != _allStatuses && row.status != status) {
        return false;
      }
      if (adviser != _allAdvisers && row.adviser != adviser) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${row.customer} ${row.vehicle} ${row.phone} ${row.jobCard} ${row.model}'
                .toLowerCase();
        if (!hay.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

List<DateTime> parseWhenDates(String when) {
  if (when.trim().isEmpty) {
    return const [];
  }
  final parts = when.split(RegExp(r'\s+and\s+', caseSensitive: false));
  final out = <DateTime>[];
  for (final part in parts) {
    final text = part.trim();
    if (text.isEmpty) {
      continue;
    }
    try {
      final parsed = _whenDateFormat.parseLoose(text);
      out.add(DateTime(parsed.year, parsed.month, parsed.day));
    } catch (_) {
      final iso = DateTime.tryParse(text);
      if (iso != null) {
        out.add(DateTime(iso.year, iso.month, iso.day));
      }
    }
  }
  return out;
}

bool _rowMatchesDate(String when, DateTime? start, DateTime? end) {
  if (start == null && end == null) {
    return true;
  }
  final dates = parseWhenDates(when);
  if (dates.isEmpty) {
    return false;
  }
  for (final day in dates) {
    if (start != null && day.isBefore(start)) {
      continue;
    }
    if (end != null && day.isAfter(end)) {
      continue;
    }
    return true;
  }
  return false;
}

List<String> _uniqueOptions(
  List<OutcomeRow> rows,
  String Function(OutcomeRow) pick,
  String allLabel,
) {
  final values = <String>{};
  for (final row in rows) {
    final text = pick(row).trim();
    if (text.isNotEmpty) {
      values.add(text);
    }
  }
  final sorted = values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [allLabel, ...sorted];
}

/// Compact Tracksheet-style filter strip for Job Card rows.
class TracksheetFilterBar extends StatefulWidget {
  const TracksheetFilterBar({
    super.key,
    required this.sourceRows,
    required this.filters,
    required this.searchController,
    required this.visibleCount,
    required this.onChanged,
    this.onExport,
  });

  final List<OutcomeRow> sourceRows;
  final TracksheetRowFilters filters;
  final TextEditingController searchController;
  final int visibleCount;
  final VoidCallback onChanged;
  final VoidCallback? onExport;

  @override
  State<TracksheetFilterBar> createState() => _TracksheetFilterBarState();
}

class _TracksheetFilterBarState extends State<TracksheetFilterBar> {
  Timer? _searchDebounce;
  List<OutcomeRow>? _cachedSource;
  List<String> _branches = const [_allBranches];
  List<String> _services = const [_allServices];
  List<String> _bookings = const [_allBookings];
  List<String> _statuses = const [_allStatuses];
  List<String> _advisers = const [_allAdvisers];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _ensureOptions() {
    if (identical(_cachedSource, widget.sourceRows)) {
      return;
    }
    _cachedSource = widget.sourceRows;
    _branches =
        _uniqueOptions(widget.sourceRows, (row) => row.branch, _allBranches);
    _services =
        _uniqueOptions(widget.sourceRows, (row) => row.service, _allServices);
    _bookings =
        _uniqueOptions(widget.sourceRows, (row) => row.booking, _allBookings);
    _statuses =
        _uniqueOptions(widget.sourceRows, (row) => row.status, _allStatuses);
    _advisers =
        _uniqueOptions(widget.sourceRows, (row) => row.adviser, _allAdvisers);
  }

  void _onSearchChanged(String value) {
    widget.filters.search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        widget.onChanged();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureOptions();
    final filters = widget.filters;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tsLine),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: TextField(
              controller: widget.searchController,
              style: const TextStyle(fontSize: 12),
              decoration: _searchDecoration(),
              onChanged: _onSearchChanged,
            ),
          ),
          _Drop(
            value: _safeValue(filters.datePreset, _datePresets),
            items: _datePresets,
            width: 120,
            onChanged: (value) {
              filters.datePreset = value;
              if (value != dateCustom) {
                filters.customFrom = null;
                filters.customTo = null;
              }
              widget.onChanged();
            },
          ),
          if (filters.datePreset == dateCustom) ...[
            _CustomDateButton(
              label: filters.customFrom == null
                  ? 'From'
                  : _shortDateFormat.format(filters.customFrom!),
              value: filters.customFrom,
              onPicked: (value) {
                filters.customFrom = value;
                if (filters.customTo != null &&
                    value != null &&
                    filters.customTo!.isBefore(value)) {
                  filters.customTo = value;
                }
                widget.onChanged();
              },
            ),
            _CustomDateButton(
              label: filters.customTo == null
                  ? 'To'
                  : _shortDateFormat.format(filters.customTo!),
              value: filters.customTo ?? filters.customFrom,
              onPicked: (value) {
                filters.customTo = value;
                if (filters.customFrom != null &&
                    value != null &&
                    value.isBefore(filters.customFrom!)) {
                  filters.customFrom = value;
                }
                widget.onChanged();
              },
            ),
          ],
          _Drop(
            value: _safeValue(filters.branch, _branches),
            items: _branches,
            onChanged: (value) {
              filters.branch = value;
              widget.onChanged();
            },
          ),
          _Drop(
            value: _safeValue(filters.service, _services),
            items: _services,
            onChanged: (value) {
              filters.service = value;
              widget.onChanged();
            },
          ),
          _Drop(
            value: _safeValue(filters.booking, _bookings),
            items: _bookings,
            onChanged: (value) {
              filters.booking = value;
              widget.onChanged();
            },
          ),
          _Drop(
            value: _safeValue(filters.status, _statuses),
            items: _statuses,
            onChanged: (value) {
              filters.status = value;
              widget.onChanged();
            },
          ),
          _Drop(
            value: _safeValue(filters.adviser, _advisers),
            items: _advisers,
            onChanged: (value) {
              filters.adviser = value;
              widget.onChanged();
            },
          ),
          Text(
            '${widget.visibleCount} of ${widget.sourceRows.length}',
            style: const TextStyle(
              color: tsMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(
            onPressed: () {
              _searchDebounce?.cancel();
              filters.clear();
              widget.searchController.clear();
              widget.onChanged();
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear', style: TextStyle(fontSize: 12)),
          ),
          if (widget.onExport != null)
            FilledButton.icon(
              onPressed: widget.onExport,
              style: glassLook(
                fill: tsGreen,
                foreground: tsWhite,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.download, size: 14),
              label: const Text('Excel', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  String _safeValue(String value, List<String> items) {
    return items.contains(value) ? value : items.first;
  }

  InputDecoration _searchDecoration() {
    return const InputDecoration(
      isDense: true,
      filled: true,
      fillColor: tsWhite,
      hintText: 'Search name, reg, phone, JC…',
      hintStyle: TextStyle(fontSize: 12),
      prefixIcon: Icon(Icons.search, size: 16, color: tsMuted),
      prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: tsLine),
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: tsLine),
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    );
  }
}

class _CustomDateButton extends StatelessWidget {
  const _CustomDateButton({
    required this.label,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPicked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
          );
          if (picked != null) {
            onPicked(DateTime(picked.year, picked.month, picked.day));
          }
        },
        style: glassLook(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop({
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 136,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: tsWhite,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: tsLine),
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: tsLine),
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 12, color: tsInk),
            value: value,
            items: items
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
          ),
        ),
      ),
    );
  }
}
