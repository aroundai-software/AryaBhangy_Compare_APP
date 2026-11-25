import 'package:aryabhangy_compare/models/compare_models.dart';
import 'package:aryabhangy_compare/services/result_store.dart';
import 'package:aryabhangy_compare/state/compare_controller.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryRunSummary _run({
  required String company,
  required String branch,
  required String to,
  required String savedAt,
}) {
  return HistoryRunSummary(
    id: savedAt,
    savedAt: savedAt,
    company: company,
    branch: branch,
    from: '2026-10-15',
    to: to,
    added: 0,
    removed: 0,
    check: 0,
    keep: 0,
    rowCount: 0,
  );
}

void main() {
  const aluva = 'Arya Bhangy Motors, Aluva - (2025-2026)';
  const perumbavoor = 'Arya Bhangy Motors, Perumbavoor - (2025-2026)';

  test('sync continues the selected branch, not another branch', () {
    final runs = [
      _run(
        company: aluva,
        branch: 'Aluva',
        to: '2026-10-30',
        savedAt: '2026-11-01T10:00:00Z',
      ),
      _run(
        company: perumbavoor,
        branch: 'Perumbavoor',
        to: '2026-11-20',
        savedAt: '2026-11-21T10:00:00Z',
      ),
    ];

    expect(
      latestToFor(company: aluva, branch: 'Aluva', runs: runs),
      '2026-10-30',
    );
    expect(
      latestToFor(company: perumbavoor, branch: 'Perumbavoor', runs: runs),
      '2026-11-20',
    );
    expect(
      latestToFor(company: perumbavoor, branch: 'Aluva', runs: runs),
      isNull,
    );
  });

  test('sync uses the latest finished run for that company and branch', () {
    final runs = [
      _run(
        company: aluva,
        branch: 'Aluva',
        to: '2026-10-30',
        savedAt: '2026-11-01T10:00:00Z',
      ),
      _run(
        company: aluva,
        branch: 'Aluva',
        to: '2026-10-10',
        savedAt: '2026-11-23T10:00:00Z',
      ),
    ];

    expect(
      latestToFor(company: aluva, branch: 'Aluva', runs: runs),
      '2026-10-10',
    );
  });

  test('a compare still saving counts for its own branch', () {
    final pending = CompareResultView(
      company: aluva,
      branch: 'Aluva',
      from: '2026-10-31',
      to: '2026-11-23',
      trackRows: 0,
      tallyRows: 0,
      uncoveredRows: 0,
      added: 0,
      removed: 0,
      check: 0,
      keep: 0,
      voucherRows: 0,
      bothMatchCount: 0,
      oneMatchCount: 0,
      notMatchingCount: 0,
      hiriseBills: 0,
      branches: const ['Aluva'],
      rows: const [],
    );

    expect(
      latestToFor(
        company: aluva,
        branch: 'Aluva',
        runs: [
          _run(
            company: aluva,
            branch: 'Aluva',
            to: '2026-10-30',
            savedAt: '2026-11-01T10:00:00Z',
          ),
        ],
        pending: pending,
      ),
      '2026-11-23',
    );
  });
}
