import 'package:flutter/material.dart';

class AppTheme {
  static const primaryPurple = Color(0xFF7C3AED);
  static const darkPurple = Color(0xFF5B21B6);
  static const lightPurple = Color(0xFFA78BFA);
  static const bgDark = Color(0xFF1F1B2E);
  static const bgCard = Color(0xFF2D2640);
  static const bgInput = Color(0xFF3D3455);
  static const textPrimary = Color(0xFFF5F3FF);
  static const textSecondary = Color(0xFFC4B5FD);
  static const errorRed = Color(0xFFEF4444);
  static const successGreen = Color(0xFF10B981);

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: primaryPurple,
          secondary: lightPurple,
          surface: bgDark,
          onSurface: textPrimary,
          onPrimary: textPrimary,
          error: errorRed,
        ),
        scaffoldBackgroundColor: bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkPurple,
          foregroundColor: textPrimary,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: bgCard,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: textSecondary),
          floatingLabelStyle: const TextStyle(color: textSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryPurple,
            foregroundColor: textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: lightPurple,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryPurple,
          foregroundColor: textPrimary,
        ),
      );
}
