import 'package:flutter/material.dart';

/// Colours aligned with Arya Bhangy Tracksheet.
const tsGreen = Color(0xFF1B4332);
const tsGreenDark = Color(0xFF143326);
const tsGreenSoft = Color(0xFFE6F2EC);
const tsBg = Color(0xFFF5F7F6);
const tsInk = Color(0xFF142A24);
const tsMuted = Color(0xFF5C5C5C);
const tsLine = Color(0xFFD6D3D1);
const tsWhite = Color(0xFFFFFFFF);
const tsRed = Color(0xFF9B2C2C);
const tsAmber = Color(0xFFB45309);
const tsAddedBg = Color(0xFFECFDF5);
const tsRemovedBg = Color(0xFFFEF2F2);
const tsCheckBg = Color(0xFFFFFBEB);

const glassQuietFill = Color(0xFFE4ECE9);

/// Pale glass for quiet buttons. Pass [fill] `tsGreen` or `tsRed` for a solid
/// action button with only a faint shine along the top.
ButtonStyle glassLook({
  Color fill = glassQuietFill,
  Color foreground = tsInk,
  Color? border,
  EdgeInsetsGeometry? padding,
  VisualDensity? visualDensity,
  Size? minimumSize,
  MaterialTapTargetSize? tapTargetSize,
  AlignmentGeometry? alignment,
}) {
  final strong = fill.computeLuminance() < 0.45;
  final edge = border ??
      (strong ? tsWhite.withValues(alpha: 0.34) : tsLine);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Color.lerp(fill, tsBg, 0.55);
      }
      return fill;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return foreground.withValues(alpha: 0.45);
      }
      return foreground;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return foreground.withValues(alpha: 0.45);
      }
      return foreground;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return tsWhite.withValues(alpha: 0.16);
      }
      if (states.contains(WidgetState.hovered)) {
        return tsWhite.withValues(alpha: strong ? 0.08 : 0.28);
      }
      return const Color(0x00000000);
    }),
    elevation: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.disabled) ? 0 : 1.5;
    }),
    shadowColor: const WidgetStatePropertyAll(Color(0x24142420)),
    surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
    side: WidgetStatePropertyAll(BorderSide(color: edge)),
    padding: padding == null ? null : WidgetStatePropertyAll(padding),
    visualDensity: visualDensity,
    minimumSize: minimumSize == null ? null : WidgetStatePropertyAll(minimumSize),
    tapTargetSize: tapTargetSize,
    alignment: alignment,
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    backgroundBuilder: (context, states, child) {
      final disabled = states.contains(WidgetState.disabled);
      final hovered = states.contains(WidgetState.hovered);
      final top = disabled
          ? 0.08
          : (strong ? 0.22 : 0.82) + (hovered ? 0.08 : 0);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: strong ? null : Border.all(color: edge),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tsWhite.withValues(alpha: top.clamp(0.0, 1.0)),
              tsWhite.withValues(alpha: strong ? 0.02 : 0.06),
            ],
          ),
        ),
        child: child,
      );
    },
  );
}
