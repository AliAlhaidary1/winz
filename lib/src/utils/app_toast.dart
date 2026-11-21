import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Short, top-anchored notification used for sale feedback so rapid sales
/// never stack up at the bottom of the screen.
void showSaleToast(
  BuildContext context,
  String message, {
  bool error = false,
  Color? color,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: (MediaQuery.of(context).size.height - 110).clamp(80.0, 10000.0),
      ),
      duration: const Duration(milliseconds: 900),
      backgroundColor: error ? AppTheme.red : (color ?? AppTheme.green),
    ),
  );
}
