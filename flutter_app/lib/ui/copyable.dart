import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Right-click menu for selectable words. Select all is left out.
Widget copyContextMenu(BuildContext context, SelectableRegionState state) {
  final items = state.contextMenuButtonItems
      .where((item) => item.type != ContextMenuButtonType.selectAll)
      .toList();
  if (items.isEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.mounted) {
        state.hideToolbar();
      }
    });
    return const SizedBox.shrink();
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: items,
  );
}

/// Copies the highlighted words. Used by Ctrl+C.
void copyHighlightedText() {
  _ActiveCopySelection.copy();
}

/// The words that are highlighted. Ctrl+C copies this text.
class _ActiveCopySelection {
  static SelectableRegionState? region;
  static String text = '';

  static void remember(SelectableRegionState next, String plainText) {
    final previous = region;
    region = next;
    text = plainText;
    if (previous != null && previous != next && previous.mounted) {
      previous.hideToolbar();
      previous.clearSelection();
    }
  }

  static void copy() {
    final value = text;
    if (value.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: value));
  }

  static void clearIfOutside(Offset globalPosition) {
    final current = region;
    if (current == null || !current.mounted) {
      region = null;
      text = '';
      return;
    }
    final object = current.context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return;
    }
    final local = object.globalToLocal(globalPosition);
    if (object.size.contains(local)) {
      return;
    }
    region = null;
    text = '';
    current.hideToolbar();
    current.clearSelection();
  }
}

/// Shows the text cursor while the pointer is over words.
///
/// Buttons keep their own click cursor. Blank space keeps the normal arrow,
/// so a click-drag there can still scroll.
class TextHoverCursor extends StatefulWidget {
  const TextHoverCursor({super.key, required this.child});

  final Widget child;

  @override
  State<TextHoverCursor> createState() => _TextHoverCursorState();
}

class _TextHoverCursorState extends State<TextHoverCursor> {
  bool _overText = false;

  void _update(Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    var overText = false;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderParagraph || target is RenderEditable) {
        overText = true;
        break;
      }
    }
    if (overText != _overText) {
      setState(() => _overText = overText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _ActiveCopySelection.clearIfOutside(event.position),
      child: MouseRegion(
        cursor: _overText ? SystemMouseCursors.text : MouseCursor.defer,
        onHover: (event) => _update(event.position, event.viewId),
        onExit: (_) {
          if (_overText) {
            setState(() => _overText = false);
          }
        },
        child: widget.child,
      ),
    );
  }
}

/// One block of text that can be dragged and copied.
///
/// Used inside a mouse-drag scroller. The selection gesture sits on the words
/// only, so a drag that starts on blank space still scrolls.
class Copyable extends StatefulWidget {
  const Copyable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Copyable> createState() => _CopyableState();
}

class _CopyableState extends State<Copyable> {
  final _areaKey = GlobalKey<SelectionAreaState>();

  void _onSelectionChanged(SelectedContent? content) {
    final region = _areaKey.currentState?.selectableRegion;
    if (region == null) {
      return;
    }
    if (content != null && content.plainText.isNotEmpty) {
      _ActiveCopySelection.remember(region, content.plainText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = MouseRegion(
      cursor: SystemMouseCursors.text,
      child: SelectionArea(
        key: _areaKey,
        contextMenuBuilder: copyContextMenu,
        onSelectionChanged: _onSelectionChanged,
        child: widget.child,
      ),
    );
    final onTap = widget.onTap;
    if (onTap == null) {
      return body;
    }
    return _CopyTap(onTap: onTap, child: body);
  }
}

/// A click still runs [onTap]. A drag is left to the selection gesture.
class _CopyTap extends StatefulWidget {
  const _CopyTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_CopyTap> createState() => _CopyTapState();
}

class _CopyTapState extends State<_CopyTap> {
  Offset? _down;
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) {
          return;
        }
        _down = event.position;
        _moved = false;
      },
      onPointerMove: (event) {
        final start = _down;
        if (start != null && (event.position - start).distance > 4) {
          _moved = true;
        }
      },
      onPointerUp: (_) {
        final start = _down;
        _down = null;
        if (start != null && !_moved) {
          widget.onTap();
        }
      },
      onPointerCancel: (_) => _down = null,
      child: widget.child,
    );
  }
}
