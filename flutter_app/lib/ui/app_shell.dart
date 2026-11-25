import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/compare_controller.dart';
import 'copyable.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final CompareController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  String? _historyOpenRunId;
  String? _historyOpenMark;
  int _historyOpenToken = 0;

  void _openHistoryRun(String? runId, String mark) {
    setState(() {
      _tab = 1;
      _historyOpenRunId = runId;
      _historyOpenMark = mark;
      _historyOpenToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tsBg,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyC, control: true):
              copyHighlightedText,
        },
        child: SelectionArea(
        contextMenuBuilder: copyContextMenu,
        child: TextHoverCursor(
        child: Column(
        children: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => _ShellTopBar(
              selected: _tab,
              branch: widget.controller.selectedBranch == allBranches
                  ? ''
                  : widget.controller.selectedBranch,
              practiceSave: widget.controller.allowPracticeSave &&
                  widget.controller.practiceSite,
              onSelect: (index) => setState(() {
                _tab = index;
                if (index != 1) {
                  _historyOpenRunId = null;
                }
              }),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                HomePage(
                  controller: widget.controller,
                  showTopBar: false,
                  onOpenHistoryRun: _openHistoryRun,
                ),
                HistoryPage(
                  controller: widget.controller,
                  active: _tab == 1,
                  openRunId: _historyOpenRunId,
                  openMark: _historyOpenMark,
                  openRunToken: _historyOpenToken,
                ),
                SettingsPage(controller: widget.controller),
              ],
            ),
          ),
        ],
        ),
        ),
        ),
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.selected,
    required this.branch,
    required this.practiceSave,
    required this.onSelect,
  });

  final int selected;
  final String branch;
  final bool practiceSave;
  final ValueChanged<int> onSelect;

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
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Arya Bhangy',
                style: TextStyle(
                  color: tsWhite,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                branch.isEmpty ? 'Compare' : 'Compare · $branch',
                style: const TextStyle(
                  color: Color(0xFFB8D0C4),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          _NavTab(
            label: 'Compare',
            selected: selected == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(width: 6),
          _NavTab(
            label: 'History',
            selected: selected == 1,
            onTap: () => onSelect(1),
          ),
          const SizedBox(width: 6),
          _NavTab(
            label: 'Settings',
            selected: selected == 2,
            onTap: () => onSelect(2),
          ),
          const Spacer(),
          Material(
            color: practiceSave
                ? const Color(0xFF0E241B)
                : const Color(0xFF78350F),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => onSelect(2),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: practiceSave
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFBBF24),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      practiceSave
                          ? 'Tracksheet  ·  saving allowed'
                          : 'Tracksheet  ·  read-only',
                      style: const TextStyle(color: tsWhite, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tsWhite.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: tsWhite,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
