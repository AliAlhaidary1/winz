import 'package:flutter/material.dart';

class AppTheme {
  static const green = Color(0xFF0B8A3E);
  static const greenDark = Color(0xFF076B2F);
  static const greenLight = Color(0xFFE6F4EA);
  static const greenSoft = Color(0xFFEFF8F1);
  static const blue = Color(0xFF1565C0);
  static const orange = Color(0xFFFF8E00);
  static const red = Color(0xFFD32F2F);
  static const bg = Color(0xFFF6F8F6);
  static const cardBorder = Color(0xFFE8EEE8);
  static const textDark = Color(0xFF1A1A1A);
  static const textMuted = Color(0xFF6B7280);

  static ThemeData light() {
    const cs = ColorScheme.light(
      primary: green,
      secondary: Color(0xFF1DB954),
      surface: Colors.white,
    );
    return ThemeData(
      colorScheme: cs,
      scaffoldBackgroundColor: bg,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: green, width: 1.4),
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: TextStyle(fontSize: 12, color: textMuted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: green,
        labelStyle: TextStyle(fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cardBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: green,
          side: BorderSide(color: green),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      dividerTheme: DividerThemeData(color: Color(0xFFEEF2EE), thickness: 1),
    );
  }

  static BoxDecoration cardDecoration({
    Color? borderColor,
    double radius = 16,
  }) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration softGreenDecoration() {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [green, greenDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: green.withValues(alpha: 0.25),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    );
  }
}
