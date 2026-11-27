const bothMatch = 'Both match';
const onlyOneMatch = 'Only one match';
const notMatching = 'Not matching';

const statusAdded = 'Added to track';
const statusRemoved = 'Removed from tracksheet';
const statusCheck = 'Check manually';
const statusKeep = 'No change';

class OutcomeRow {
  const OutcomeRow({
    required this.mark,
    required this.category,
    required this.jobCard,
    required this.vehicle,
    required this.customer,
    required this.when,
    required this.adviser,
    required this.branch,
    required this.reason,
    required this.tallyBills,
    required this.trackBill,
    required this.amount,
    required this.status,
    required this.service,
    required this.phone,
    required this.model,
    required this.booking,
    required this.technician,
    required this.labour,
    required this.spares,
    required this.vas,
    required this.payment,
    required this.items,
    this.tallyLabour = '',
    this.tallySpares = '',
    this.tallyVas = '',
    this.tallyTotal = '',
    this.tallyWhen = '',
    this.sheetBill = '',
    this.sheetLabour = '',
    this.sheetSpares = '',
    this.sheetTotal = '',
    this.sheetVas = '',
    this.sheetWhen = '',
    this.sheetKnown = false,
    this.sheetRowId = 0,
  });

  final String mark;
  final String category;
  final String jobCard;
  final String vehicle;
  final String customer;
  final String when;
  final String adviser;
  final String branch;
  final String reason;
  final String tallyBills;
  final String trackBill;
  final String amount;
  final String status;
  final String service;
  final String phone;
  final String model;
  final String booking;
  final String technician;
  final String labour;
  final String spares;
  final String vas;
  final String payment;
  final String items;
  final String tallyLabour;
  final String tallySpares;
  final String tallyVas;
  final String tallyTotal;
  final String tallyWhen;
  final String sheetBill;
  final String sheetLabour;
  final String sheetSpares;
  final String sheetTotal;
  final String sheetVas;
  final String sheetWhen;
  final bool sheetKnown;
  final int sheetRowId;

  factory OutcomeRow.fromJson(Map<String, dynamic> json) {
    final mark = (json['mark'] ?? '').toString();
    final category = (json['category'] ?? '').toString();
    return OutcomeRow(
      mark: mark,
      category: category.isNotEmpty ? category : _categoryFromMark(mark),
      jobCard: (json['job_card'] ?? '').toString(),
      vehicle: (json['vehicle'] ?? '').toString(),
      customer: (json['customer'] ?? '').toString(),
      when: (json['when'] ?? '').toString(),
      adviser: (json['adviser'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      tallyBills: (json['tally_bills'] ?? '').toString(),
      trackBill: (json['track_bill'] ?? '').toString(),
      amount: (json['amount'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      service: (json['service'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      booking: (json['booking'] ?? '').toString(),
      technician: (json['technician'] ?? '').toString(),
      labour: (json['labour'] ?? '').toString(),
      spares: (json['spares'] ?? '').toString(),
      vas: (json['vas'] ?? '').toString(),
      payment: (json['payment'] ?? '').toString(),
      items: (json['items'] ?? '').toString(),
      tallyLabour: (json['tally_labour'] ?? '').toString(),
      tallySpares: (json['tally_spares'] ?? '').toString(),
      tallyVas: (json['tally_vas'] ?? '').toString(),
      tallyTotal: (json['tally_total'] ?? '').toString(),
      tallyWhen: (json['tally_when'] ?? '').toString(),
      sheetBill: (json['sheet_bill'] ?? '').toString(),
      sheetLabour: (json['sheet_labour'] ?? '').toString(),
      sheetSpares: (json['sheet_spares'] ?? '').toString(),
      sheetTotal: (json['sheet_total'] ?? '').toString(),
      sheetVas: (json['sheet_vas'] ?? '').toString(),
      sheetWhen: (json['sheet_when'] ?? '').toString(),
      sheetKnown: json.containsKey('sheet_bill'),
      sheetRowId: int.tryParse('${json['sheet_row_id'] ?? ''}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'mark': mark,
        'category': category,
        'job_card': jobCard,
        'vehicle': vehicle,
        'customer': customer,
        'when': when,
        'adviser': adviser,
        'branch': branch,
        'reason': reason,
        'tally_bills': tallyBills,
        'track_bill': trackBill,
        'amount': amount,
        'status': status,
        'service': service,
        'phone': phone,
        'model': model,
        'booking': booking,
        'technician': technician,
        'labour': labour,
        'spares': spares,
        'vas': vas,
        'payment': payment,
        'items': items,
        if (sheetKnown) 'tally_labour': tallyLabour,
        if (sheetKnown) 'tally_spares': tallySpares,
        if (sheetKnown) 'tally_vas': tallyVas,
        if (sheetKnown) 'tally_total': tallyTotal,
        if (sheetKnown) 'tally_when': tallyWhen,
        if (sheetKnown) 'sheet_bill': sheetBill,
        if (sheetKnown) 'sheet_labour': sheetLabour,
        if (sheetKnown) 'sheet_spares': sheetSpares,
        if (sheetKnown) 'sheet_total': sheetTotal,
        if (sheetKnown) 'sheet_vas': sheetVas,
        if (sheetKnown) 'sheet_when': sheetWhen,
        'sheet_row_id': sheetRowId,
      };
}

class VoucherRowView {
  const VoucherRowView({
    required this.voucherNumber,
    required this.when,
    required this.branch,
    required this.registration,
    required this.jobCard,
    required this.hasJobCard,
    required this.labour,
    required this.spares,
    required this.vas,
    required this.items,
    required this.note,
  });

  final String voucherNumber;
  final String when;
  final String branch;
  final String registration;
  final String jobCard;
  final bool hasJobCard;
  final String labour;
  final String spares;
  final String vas;
  final String items;
  final String note;

  factory VoucherRowView.fromJson(Map<String, dynamic> json) {
    return VoucherRowView(
      voucherNumber: (json['voucher_number'] ?? '').toString(),
      when: (json['when'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      registration: (json['registration'] ?? '').toString(),
      jobCard: (json['job_card'] ?? '').toString(),
      hasJobCard: json['has_job_card'] == true,
      labour: (json['labour'] ?? '').toString(),
      spares: (json['spares'] ?? '').toString(),
      vas: (json['vas'] ?? '').toString(),
      items: (json['items'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'voucher_number': voucherNumber,
        'when': when,
        'branch': branch,
        'registration': registration,
        'job_card': jobCard,
        'has_job_card': hasJobCard,
        'labour': labour,
        'spares': spares,
        'vas': vas,
        'items': items,
        'note': note,
      };
}

class CompareResultView {
  const CompareResultView({
    required this.company,
    required this.branch,
    required this.from,
    required this.to,
    required this.trackRows,
    required this.tallyRows,
    required this.uncoveredRows,
    required this.added,
    required this.removed,
    required this.check,
    required this.keep,
    required this.voucherRows,
    required this.bothMatchCount,
    required this.oneMatchCount,
    required this.notMatchingCount,
    required this.hiriseBills,
    required this.branches,
    required this.rows,
    this.vouchers = const [],
    this.savedAt = '',
  });

  final String company;
  final String branch;
  final String from;
  final String to;
  final int trackRows;
  final int tallyRows;
  final int uncoveredRows;
  final int added;
  final int removed;
  final int check;
  final int keep;
  final int voucherRows;
  final int bothMatchCount;
  final int oneMatchCount;
  final int notMatchingCount;
  final int hiriseBills;
  final List<String> branches;
  final List<OutcomeRow> rows;
  final List<VoucherRowView> vouchers;
  final String savedAt;

  factory CompareResultView.fromJson(Map<String, dynamic> json) {
    final rows = <OutcomeRow>[];
    final rawRows = json['rows'];
    if (rawRows is List) {
      for (final item in rawRows) {
        if (item is Map<String, dynamic>) {
          rows.add(OutcomeRow.fromJson(item));
        } else if (item is Map) {
          rows.add(OutcomeRow.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final vouchers = <VoucherRowView>[];
    final rawVouchers = json['vouchers'];
    if (rawVouchers is List) {
      for (final item in rawVouchers) {
        if (item is Map<String, dynamic>) {
          vouchers.add(VoucherRowView.fromJson(item));
        } else if (item is Map) {
          vouchers.add(VoucherRowView.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final branches = <String>[];
    final rawBranches = json['branches'];
    if (rawBranches is List) {
      for (final item in rawBranches) {
        final text = item.toString();
        if (text.isNotEmpty) {
          branches.add(text);
        }
      }
    }
    final added = _asInt(json['added']);
    final removed = _asInt(json['removed']);
    final check = _asInt(json['check']);
    final keep = json.containsKey('keep')
        ? _asInt(json['keep'])
        : rows.where((row) => row.mark == statusKeep).length;
    return CompareResultView(
      company: (json['company'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      from: (json['from'] ?? '').toString(),
      to: (json['to'] ?? '').toString(),
      trackRows: _asInt(json['track_rows']),
      tallyRows: _asInt(json['tally_rows']),
      uncoveredRows: _asInt(json['uncovered_rows']),
      added: added,
      removed: removed,
      check: check,
      keep: keep,
      voucherRows: json.containsKey('voucher_rows')
          ? _asInt(json['voucher_rows'])
          : vouchers.length,
      bothMatchCount: json.containsKey('both_match')
          ? _asInt(json['both_match'])
          : rows.where((row) => row.category == bothMatch).length,
      oneMatchCount: json.containsKey('one_match')
          ? _asInt(json['one_match'])
          : rows.where((row) => row.category == onlyOneMatch).length,
      notMatchingCount: json.containsKey('not_matching')
          ? _asInt(json['not_matching'])
          : rows.where((row) => row.category == notMatching).length,
      hiriseBills: _asInt(json['hirise_bills']),
      branches: branches,
      rows: rows,
      vouchers: vouchers,
      savedAt: (json['saved_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'event': 'compare.result',
        'company': company,
        'branch': branch,
        'from': from,
        'to': to,
        'track_rows': trackRows,
        'tally_rows': tallyRows,
        'uncovered_rows': uncoveredRows,
        'added': added,
        'removed': removed,
        'check': check,
        'keep': keep,
        'voucher_rows': voucherRows,
        'both_match': bothMatchCount,
        'one_match': oneMatchCount,
        'not_matching': notMatchingCount,
        'hirise_bills': hiriseBills,
        'branches': branches,
        'rows': rows.map((row) => row.toJson()).toList(),
        'vouchers': vouchers.map((row) => row.toJson()).toList(),
        'saved_at': savedAt,
      };

  CompareResultView copyWith({String? savedAt}) {
    return CompareResultView(
      company: company,
      branch: branch,
      from: from,
      to: to,
      trackRows: trackRows,
      tallyRows: tallyRows,
      uncoveredRows: uncoveredRows,
      added: added,
      removed: removed,
      check: check,
      keep: keep,
      voucherRows: voucherRows,
      bothMatchCount: bothMatchCount,
      oneMatchCount: oneMatchCount,
      notMatchingCount: notMatchingCount,
      hiriseBills: hiriseBills,
      branches: branches,
      rows: rows,
      vouchers: vouchers,
      savedAt: savedAt ?? this.savedAt,
    );
  }
}

String _categoryFromMark(String mark) {
  switch (mark) {
    case statusKeep:
    case 'Keep':
      return bothMatch;
    case statusAdded:
    case statusRemoved:
    case 'Added':
    case 'Removed':
      return notMatching;
    default:
      return onlyOneMatch;
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value') ?? 0;
}
