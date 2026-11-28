import 'dart:ui' show ImageFilter;

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

class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
  int _tab = 0;
  int _fromTab = 0;
  int _slideSerial = 0;
  String? _historyOpenRunId;
  String? _historyOpenMark;
  int _historyOpenToken = 0;
  int _shownHistoryToken = 0;
  String? _shownHistoryRunId;
  String? _shownHistoryMark;
  late final AnimationController _pages;
  late final CurvedAnimation _pageSlide;

  @override
  void initState() {
    super.initState();
    _pages = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    )..addStatusListener(_onPageSettled);
    _pageSlide = CurvedAnimation(parent: _pages, curve: Curves.easeOutQuart);
  }

  void _onPageSettled(AnimationStatus status) {
    if (status == AnimationStatus.completed && _fromTab != _tab && mounted) {
      setState(() {
        _fromTab = _tab;
        _showHistoryOpen();
      });
    }
  }

  void _showHistoryOpen() {
    _shownHistoryToken = _historyOpenToken;
    _shownHistoryRunId = _historyOpenRunId;
    _shownHistoryMark = _historyOpenMark;
  }

  bool get _pageMoving => _fromTab != _tab;

  @override
  void dispose() {
    _pages.removeStatusListener(_onPageSettled);
    _pageSlide.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _moveTo(int index) {
    if (index == _tab) {
      return;
    }
    setState(() {
      _fromTab = _tab;
      _tab = index;
    });
    _startSlide();
  }

  /// Lays the destination out while it is still off-screen, then starts the
  /// clock. Starting the clock first lets a heavy page use up the whole glide.
  void _startSlide() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.value = 1;
      setState(() {
        _fromTab = _tab;
        _showHistoryOpen();
      });
      return;
    }
    final serial = ++_slideSerial;
    _pages.value = 0;
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted || serial != _slideSerial || _fromTab == _tab) {
        return;
      }
      _pages.forward();
    });
  }

  void _selectTab(int index) {
    if (index != 1) {
      _historyOpenRunId = null;
      _historyOpenMark = null;
    }
    _moveTo(index);
  }

  /// History keeps an open run painted until the slide has left the screen.
  bool get _historyActive => _tab == 1 || (_fromTab == 1 && _pageMoving);

  bool get _historySettled => _tab == 1 && !_pageMoving;

  void _openHistoryRun(String? runId, String mark) {
    final changed = _tab != 1;
    setState(() {
      if (changed) {
        _fromTab = _tab;
      }
      _tab = 1;
      _historyOpenRunId = runId;
      _historyOpenMark = mark;
      _historyOpenToken++;
      _showHistoryOpen();
    });
    if (!changed) {
      return;
    }
    _startSlide();
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
              onSelect: _selectTab,
            ),
          ),
          Expanded(
            child: _GlassPageSwitch(
              animation: _pageSlide,
              index: _tab,
              from: _fromTab,
              children: [
                HomePage(
                  controller: widget.controller,
                  showTopBar: false,
                  onOpenHistoryRun: _openHistoryRun,
                ),
                HistoryPage(
                  controller: widget.controller,
                  active: _historyActive,
                  settled: _historySettled,
                  motion: _pageMoving,
                  openRunId: _shownHistoryRunId,
                  openMark: _shownHistoryMark,
                  openRunToken: _shownHistoryToken,
                  onHome: () => _selectTab(0),
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
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
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
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Material(
                    color: practiceSave
                        ? const Color(0xFF0E241B)
                        : const Color(0xFF78350F),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: () => onSelect(2),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  const SizedBox(height: 2),
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
            ],
          ),
          _GlassTabs(selected: selected, onSelect: onSelect),
        ],
      ),
    );
  }
}

class _GlassTabs extends StatefulWidget {
  const _GlassTabs({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<_GlassTabs> createState() => _GlassTabsState();
}

class _GlassTabsState extends State<_GlassTabs> {
  static const _labels = ['Compare', 'History', 'Settings'];

  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _tabKeys = List.generate(3, (_) => GlobalKey());
  int? _hover;
  bool _pillReady = false;
  bool _animatePill = false;
  double _pillLeft = 0;
  double _pillTop = 0;
  double _pillWidth = 0;
  double _pillHeight = 0;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        if (_pillReady)
          AnimatedPositioned(
            duration: _animatePill
                ? const Duration(milliseconds: 280)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            left: _pillLeft,
            top: _pillTop,
            width: _pillWidth,
            height: _pillHeight,
            child: IgnorePointer(
              child: _GlassPill(bright: _hover == widget.selected),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _GlassTab(
                key: _tabKeys[i],
                label: _labels[i],
                selected: widget.selected == i,
                hovered: _hover == i,
                onHover: (hovering) => setState(() {
                  _hover = hovering ? i : (_hover == i ? null : _hover);
                }),
                onTap: () => widget.onSelect(i),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _measure() {
    if (!mounted) {
      return;
    }
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final tabBox =
        _tabKeys[widget.selected].currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        tabBox == null ||
        !stackBox.hasSize ||
        !tabBox.hasSize ||
        !stackBox.attached ||
        !tabBox.attached) {
      return;
    }
    final origin = tabBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final left = origin.dx;
    final top = origin.dy;
    final width = tabBox.size.width;
    final height = tabBox.size.height;
    final moved = !_pillReady ||
        (left - _pillLeft).abs() > 0.5 ||
        (top - _pillTop).abs() > 0.5 ||
        (width - _pillWidth).abs() > 0.5 ||
        (height - _pillHeight).abs() > 0.5;
    if (!moved) {
      return;
    }
    final first = !_pillReady;
    setState(() {
      _pillLeft = left;
      _pillTop = top;
      _pillWidth = width;
      _pillHeight = height;
      _pillReady = true;
      if (first) {
        _animatePill = false;
      }
    });
    if (first) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _animatePill = true);
        }
      });
    }
  }
}

class _GlassTab extends StatelessWidget {
  const _GlassTab({
    super.key,
    required this.label,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showHover = hovered && !selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.transparent,
            highlightColor: tsWhite.withValues(alpha: 0.04),
            splashColor: tsWhite.withValues(alpha: 0.12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: showHover ? tsWhite.withValues(alpha: 0.10) : const Color(0x00FFFFFF),
                border: Border.all(
                  color: showHover
                      ? tsWhite.withValues(alpha: 0.28)
                      : const Color(0x00FFFFFF),
                ),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: selected || hovered
                      ? tsWhite
                      : tsWhite.withValues(alpha: 0.86),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.bright});

  final bool bright;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: bright ? 1 : 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, glare, _) {
        final top = 0.22 + (0.10 * glare);
        final bottom = 0.08 + (0.06 * glare);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0x22000000),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tsWhite.withValues(alpha: top),
                      tsWhite.withValues(alpha: bottom),
                    ],
                  ),
                  border: Border.all(
                    color: tsWhite.withValues(alpha: 0.30 + (0.16 * glare)),
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassPageSwitch extends StatelessWidget {
  const _GlassPageSwitch({
    required this.animation,
    required this.index,
    required this.from,
    required this.children,
  });

  final Animation<double> animation;
  final int index;
  final int from;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          final moving = index != from && t < 1;
          final direction = index >= from ? 1.0 : -1.0;
          return Stack(
            fit: StackFit.loose,
            alignment: Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            children: [
              for (var i = 0; i < children.length; i++)
                Visibility(
                  visible: i == index || (moving && i == from),
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: ExcludeFocus(
                    excluding: i != index,
                    child: IgnorePointer(
                      ignoring: i != index || moving,
                      child: FractionalTranslation(
                        translation: Offset(_slide(i, t, moving, direction), 0),
                        transformHitTests: false,
                        child: RepaintBoundary(child: children[i]),
                      ),
                    ),
                  ),
                ),
              if (moving)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment(direction * (1 - (2 * t)), 0),
                      child: const FractionallySizedBox(
                        widthFactor: 0.16,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0x00FFFFFF),
                                Color(0x24FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _slide(int i, double t, bool moving, double direction) {
    if (!moving) {
      return 0;
    }
    if (i == index) {
      return direction * (1 - t);
    }
    if (i == from) {
      return -direction * t;
    }
    return 0;
  }
}
