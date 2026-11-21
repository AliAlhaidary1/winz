import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext c) => MediaQuery.of(c).size.width < 600;
  static bool isTablet(BuildContext c) =>
      MediaQuery.of(c).size.width >= 600 && MediaQuery.of(c).size.width < 1024;
  static bool isDesktop(BuildContext c) => MediaQuery.of(c).size.width >= 1024;
  static bool isLargeTablet(BuildContext c) =>
      MediaQuery.of(c).size.width >= 834;
  static bool isPortrait(BuildContext c) =>
      MediaQuery.of(c).orientation == Orientation.portrait;
  static bool isLandscape(BuildContext c) =>
      MediaQuery.of(c).orientation == Orientation.landscape;
  static bool isIPad(BuildContext c) =>
      isTablet(c) ||
      (isDesktop(c) && MediaQuery.of(c).size.shortestSide >= 768);

  static int gridCrossAxisCount(
    BuildContext c, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 4,
  }) {
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
    if (w >= 1024) return 2.1;
    if (w >= 600) return 2.0;
    return 1.8;
  }

  static double contentMaxWidth(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    if (w >= 1366) return 1100;
    if (w >= 1024) return 980;
    if (w >= 834) return 860;
    if (w >= 600) return 760;
    return double.infinity;
  }

  static double cardPadding(BuildContext c) =>
      isTablet(c) || isDesktop(c) ? 20 : 14;
  static double fontScale(BuildContext c) =>
      isTablet(c) || isDesktop(c) ? 1.1 : 1.0;
  static double buttonHeight(BuildContext c) =>
      isTablet(c) || isDesktop(c) ? 52 : 48;
  static double digitBoxSize(BuildContext c) =>
      isTablet(c) || isDesktop(c) ? 60 : 48;
}

Widget responsiveCenter({required Widget child, double? maxWidth}) {
  return Builder(
    builder: (context) {
      final mw = maxWidth ?? Responsive.contentMaxWidth(context);
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mw),
          child: child,
        ),
      );
    },
  );
}

Widget responsivePadding({
  required BuildContext context,
  required Widget child,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(
      horizontal: Responsive.horizontalPadding(context),
    ),
    child: child,
  );
}
