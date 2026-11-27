import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/compare_models.dart';
import '../state/compare_controller.dart';
import 'check_review.dart';
import 'theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    this.showTopBar = true,
    this.onOpenHistoryRun,
  });

  final CompareController controller;
  final bool showTopBar;
  final void Function(String? runId, String mark)? onOpenHistoryRun;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderRow(controller: controller),
              const SizedBox(height: 14),
              _FilterBar(controller: controller),
              const SizedBox(height: 14),
              Expanded(
                child: _CompareAftermath(
                  controller: controller,
                  onOpenHistoryRun: onOpenHistoryRun,
                ),
              ),
              const SizedBox(height: 6),
              _Footer(controller: controller),
            ],
          ),
        );
        if (!showTopBar) {
          return ColoredBox(color: tsBg, child: body);
        }
        return Scaffold(
          backgroundColor: tsBg,
          body: Column(
            children: [
              const _LegacyTopBar(),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

class _LegacyTopBar extends StatelessWidget {
  const _LegacyTopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      color: tsGreen,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: tsWhite.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: const Text(
              'A',
              style: TextStyle(
                color: tsWhite,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Arya Bhangy',
            style: TextStyle(
              color: tsWhite,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          const Text(
            'Hirise Invoice Service',
            style: TextStyle(color: Color(0xFFB8D0C4), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.controller});

  final CompareController controller;

  @override
  Widget build(BuildContext context) {
    final online = controller.tallyOnline;
    final company = controller.company;
    final tallyLabel = !online
        ? 'Tally offline'
        : company.isEmpty
        ? 'Tally online — no company'
        : company;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Job Cards compare',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: tsInk,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Match Tracksheet Job Cards with Tally Hirise bills, then export Excel for hand update.',
                style: TextStyle(color: tsMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: online ? tsAddedBg : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: online ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
            ),
          ),
          child: Row(
            children: [
              Icon(
                online ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: online ? tsGreen : tsRed,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  tallyLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: online ? tsGreen : tsRed,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompareAftermath extends StatelessWidget {
  const _CompareAftermath({required this.controller, this.onOpenHistoryRun});

  final CompareController controller;
  final void Function(String? runId, String mark)? onOpenHistoryRun;

  @override
  Widget build(BuildContext context) {
    if (controller.busy) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Reading Tracksheet and Tally…',
              style: TextStyle(color: tsMuted),
            ),
          ],
        ),
      );
    }

    final result = controller.result;
    if (result == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const Text(
            'Choose branch and dates, then Run compare.\n'
            'When it finishes, you will get a short run receipt here.\n'
            'Open History for the full Tracksheet-style Job Cards table.',
            textAlign: TextAlign.center,
            style: TextStyle(color: tsMuted, fontSize: 14, height: 1.45),
          ),
        ),
      );
    }

    final savedAt = DateTime.tryParse(result.savedAt)?.toLocal();
    final savedLabel = savedAt == null
        ? (result.savedAt.isEmpty ? 'Just now' : result.savedAt)
        : DateFormat('dd-MM-yyyy, h:mm a').format(savedAt);

    final checks = result.rows.where((row) => row.mark == statusCheck).toList();
    final reviewed = checks
        .where((row) => controller.wasWritten(row, runId: controller.lastHistoryRunId))
        .length;
    final partial = checks.where((row) {
      final cause = checkCause(row.reason);
      return cause == 'Total differs' || cause == 'Bill number differs';
    }).length;
    void open(String mark) {
      onOpenHistoryRun?.call(controller.lastHistoryRunId, mark);
    }

    return SingleChildScrollView(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: tsWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tsLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: tsLine)),
                  ),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Compare finished',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tsInk,
                        ),
                      ),
                      _Meta(label: 'Branch', value: result.branch),
                      _Meta(label: 'Period', value: '${result.from}  →  ${result.to}'),
                      if (result.company.isNotEmpty)
                        _Meta(label: 'Company', value: result.company),
                      _Meta(label: 'Saved', value: savedLabel),
                      Text(
                        '${result.rows.length} total rows',
                        style: const TextStyle(color: tsMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _KpiCard(
                            title: 'Added to track',
                            count: result.added,
                            note: 'Matched job card and vehicle. Ready to write.',
                            accent: const Color(0xFF047857),
                            background: const Color(0xFFECFDF5),
                            border: const Color(0xFFA7F3D0),
                            onTap: () => open(statusAdded),
                          ),
                          _KpiCard(
                            title: 'Check manually',
                            count: result.check,
                            note: partial == 0
                                ? 'Open the side-by-side review.'
                                : '$partial partial matches',
                            extra: checks.isEmpty
                                ? null
                                : '$reviewed/${checks.length} written',
                            accent: const Color(0xFF92400E),
                            background: const Color(0xFFFFFBEB),
                            border: const Color(0xFFFBBF24),
                            emphasize: true,
                            onTap: () => open(statusCheck),
                          ),
                          _KpiCard(
                            title: 'Removed from sheet',
                            count: result.removed,
                            note: 'Provisional. Nothing is deleted.',
                            accent: const Color(0xFF9F1239),
                            background: const Color(0xFFFFF1F2),
                            border: const Color(0xFFFECDD3),
                            onTap: () => open(statusRemoved),
                          ),
                          _KpiCard(
                            title: 'No change',
                            count: result.keep,
                            note: 'Bill #, Labour, Spares, Total, VAS, and Items already match.',
                            accent: const Color(0xFF334155),
                            background: const Color(0xFFF8FAFC),
                            border: const Color(0xFFE2E8F0),
                            onTap: () => open(statusKeep),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Write all saves Bill #, Labour, Spares, Total, VAS, and Items for Added to track. No change is already the same, so it is left as it is.',
                        style: TextStyle(color: tsMuted, fontSize: 12, height: 1.35),
                      ),
                      if (controller.writeBlockedNote.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            controller.writeBlockedNote,
                            style: const TextStyle(color: tsMuted, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: onOpenHistoryRun == null
                                ? null
                                : () => open(statusCheck),
                            style: FilledButton.styleFrom(
                              backgroundColor: tsGreen,
                              foregroundColor: tsWhite,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: Text('Review ${result.check} manual checks'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                controller.canWriteToPractice &&
                                    controller.writeAllCount(result.rows) > 0
                                ? () => controller.writeAll(result.rows)
                                : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tsGreen,
                              side: const BorderSide(color: tsGreen),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: Text(
                              'Write all (${controller.writeAllCount(result.rows)})',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: onOpenHistoryRun == null
                                ? null
                                : () => open(statusAdded),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tsInk,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            child: const Text('Open this run in History'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _export(context, controller),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tsInk,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.table_view_outlined, size: 18),
                            label: const Text('Export Excel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _export(
    BuildContext context,
    CompareController controller,
  ) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Tracksheet update Excel',
      fileName: 'Aryabhangy_tracksheet_update.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null || path.isEmpty) {
      return;
    }
    final normalized = path.toLowerCase().endsWith('.xlsx')
        ? path
        : '$path.xlsx';
    controller.saveExcel(normalized);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: tsMuted, fontSize: 11)),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            value.isEmpty ? '—' : value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: tsInk,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.count,
    required this.note,
    required this.accent,
    required this.background,
    required this.border,
    required this.onTap,
    this.extra,
    this.emphasize = false,
  });

  final String title;
  final int count;
  final String note;
  final String? extra;
  final Color accent;
  final Color background;
  final Color border;
  final bool emphasize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: emphasize ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Text('→', style: TextStyle(color: accent, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        color: accent,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    if (extra != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          extra!,
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note,
                  style: TextStyle(color: accent.withValues(alpha: 0.85), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final CompareController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tsWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.voucherTypesPrompt.isNotEmpty) ...[
            Text(
              controller.voucherTypesPrompt,
              style: const TextStyle(
                color: tsAmber,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _Labeled(
            label: 'Branch',
            child: SizedBox(
              width: 200,
              child: InputDecorator(
                decoration: _inputDecoration(),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value:
                        controller.branches.contains(controller.selectedBranch)
                        ? controller.selectedBranch
                        : allBranches,
                    items: controller.branches
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: controller.busy ? null : controller.setBranch,
                  ),
                ),
              ),
            ),
          ),
          _DateButton(
            label: 'From',
            value: controller.fromDate,
            enabled: !controller.busy,
            format: controller.formatDate,
            onPicked: controller.setFrom,
          ),
          _DateButton(
            label: 'To',
            value: controller.toDate,
            enabled: !controller.busy,
            format: controller.formatDate,
            onPicked: controller.setTo,
          ),
          FilledButton.icon(
            onPressed: controller.busy ||
                    controller.starting ||
                    controller.voucherTypesPrompt.isNotEmpty
                ? null
                : controller.runCompare,
            style: FilledButton.styleFrom(
              backgroundColor: tsGreen,
              foregroundColor: tsWhite,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(
              controller.busy ? Icons.hourglass_top : Icons.play_arrow_rounded,
            ),
            label: Text(controller.busy ? 'Running…' : 'Run compare'),
          ),
          OutlinedButton.icon(
            onPressed: controller.busy ||
                    controller.starting ||
                    controller.voucherTypesPrompt.isNotEmpty
                ? null
                : controller.syncFromLast,
            style: OutlinedButton.styleFrom(
              foregroundColor: tsGreen,
              side: const BorderSide(color: tsGreen),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Sync from last'),
          ),
          OutlinedButton.icon(
            onPressed: controller.result == null || controller.busy
                ? null
                : () => _export(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: tsGreen,
              side: const BorderSide(color: tsGreen),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('Export Excel'),
          ),
        ],
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Tracksheet update Excel',
      fileName: 'Aryabhangy_tracksheet_update.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null || path.isEmpty) {
      return;
    }
    final normalized = path.toLowerCase().endsWith('.xlsx')
        ? path
        : '$path.xlsx';
    controller.saveExcel(normalized);
  }
}

InputDecoration _inputDecoration() {
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

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.enabled,
    required this.format,
    required this.onPicked,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final String Function(DateTime) format;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return _Labeled(
      label: label,
      child: SizedBox(
        width: 150,
        child: OutlinedButton(
          onPressed: !enabled
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: value,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    onPicked(picked);
                  }
                },
          style: OutlinedButton.styleFrom(
            backgroundColor: tsWhite,
            foregroundColor: tsInk,
            side: const BorderSide(color: tsLine),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(format(value), overflow: TextOverflow.ellipsis),
              ),
              Icon(
                Icons.calendar_month,
                size: 16,
                color: enabled ? tsGreen : tsMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});

  final CompareController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.lastError;
    if (error == null || error.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      error,
      style: const TextStyle(color: tsRed, fontSize: 12),
    );
  }
}
