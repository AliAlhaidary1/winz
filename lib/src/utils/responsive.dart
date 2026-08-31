import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext c) => MediaQuery.of(c).size.width < 600;
  static bool isTablet(BuildContext c) => MediaQuery.of(c).size.width >= 600 && MediaQuery.of(c).size.width < 1024;
  static bool isDesktop(BuildContext c) => MediaQuery.of(c).size.width >= 1024;

  static int gridCrossAxisCount(BuildContext c, {int mobile = 2, int tablet = 3, int desktop = 4}) {
    final w = MediaQuery.of(c).size.width;
    if (w >= 1024) return desktop;
    if (w >= 600) return tablet;
    return mobile;
  }

  static double horizontalPadding(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    if (w >= 1024) return 32;
    if (w >= 600) return 20;
    return 14;
  }

  static double keypadChildAspectRatio(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    if (w < 360) return 2.4;
    if (w < 400) return 2.2;
    return 2.0;
  }
}

Widget responsiveCenter({required Widget child, double maxWidth = 720}) {
  return Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
