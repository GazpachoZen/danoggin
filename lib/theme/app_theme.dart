// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: AppColors.deepBlue,
      colorScheme: ColorScheme.light(
        primary: AppColors.deepBlue,
        secondary: AppColors.coral,
        surface: AppColors.offWhite,        // Replaces 'background'
        surfaceContainerHighest: Colors.white,  // Additional surface variant
        onPrimary: AppColors.offWhite,
        onSecondary: AppColors.textDark,
        onSurface: AppColors.textDark,      // Replaces 'onBackground'
      ),
      scaffoldBackgroundColor: AppColors.offWhite,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepBlue,
        foregroundColor: AppColors.offWhite,
        elevation: 0,
      ),
// In lib/theme/app_theme.dart
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              AppColors.lightGray, // Changed from midBlue to lightGray
          foregroundColor: AppColors
              .textDark, // Changed text color to dark for better contrast
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.deepBlue,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.midBlue,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE0E0E0),
        thickness: 1,
      ),
    );
  }
}
