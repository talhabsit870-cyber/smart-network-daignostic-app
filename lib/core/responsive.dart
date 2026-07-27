import 'package:flutter/material.dart';

import 'theme.dart';

/// Constrains and centers content so the app doesn't stretch edge-to-edge
/// on wide/desktop viewports (this app also ships to Web/Windows/Linux/
/// macOS). A no-op on phone-width screens: [maxContentWidth] is wider than
/// any phone, so [ConstrainedBox] never actually binds there and mobile
/// layout is pixel-identical to before. `Align(topCenter)` (not `Center`)
/// so horizontal centering doesn't disturb a parent's vertical
/// `spaceBetween` rhythm.
class AppBody extends StatelessWidget {
  static const double maxContentWidth = 600;

  final Widget child;

  const AppBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}

/// The shared dark gradient backdrop for every screen (Home/Result/History),
/// so the app doesn't look like only the launcher screen got design
/// attention.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, AppColors.bgBottom],
        ),
      ),
      child: child,
    );
  }
}
