import 'dart:math';
import 'package:flutter/material.dart';

/// Responsive layout breakpoints and helpers for desktop/mobile adaptation.
class ResponsiveLayout {
  /// Width threshold where we switch from mobile to desktop layout.
  static const double desktopBreakpoint = 600.0;

  /// Left sidebar width for desktop layout.
  static const double sidebarWidth = 280.0;

  /// Max bubble width on desktop to prevent overly long lines.
  static double maxBubbleWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < desktopBreakpoint) return width * 0.7;
    return (width - sidebarWidth) * 0.65;
  }

  /// Whether the current screen width qualifies as desktop.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  /// Safe bubble max width for any context.
  static double bubbleMaxWidth(BuildContext context) =>
      isDesktop(context)
          ? min(600.0, (MediaQuery.of(context).size.width - sidebarWidth) * 0.65)
          : MediaQuery.of(context).size.width * 0.7;

  /// Scaffold builder that swaps between mobile and desktop layouts.
  static Widget scaffold({
    required BuildContext context,
    required Widget mobile,
    required Widget desktop,
  }) {
    return isDesktop(context) ? desktop : mobile;
  }

  /// Shortcut to wrap a widget only on desktop.
  static Widget desktopOnly(BuildContext context, Widget child) {
    if (!isDesktop(context)) return const SizedBox.shrink();
    return child;
  }

  /// Keyboard shortcut helper — registers a ShortcutActivator + VoidCallback.
  static Widget withShortcut({
    required Widget child,
    required SingleActivator activator,
    required VoidCallback onInvoke,
  }) {
    return CallbackShortcuts(
      bindings: {activator: onInvoke},
      child: Focus(autofocus: true, child: child),
    );
  }
}
