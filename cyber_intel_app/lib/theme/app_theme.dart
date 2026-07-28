import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for QuantX.
///
/// Every colour, radius and spacing value used in the app comes from here.
/// Previously these were hard-coded hex literals scattered across widgets,
/// which is why screens drifted apart visually.
class AppColors {
  // Surfaces — a 4-step elevation ramp rather than two arbitrary greys.
  static const bg = Color(0xFF0B0F14);
  static const surface = Color(0xFF121820);
  static const surfaceRaised = Color(0xFF18202A);
  static const surfaceHigh = Color(0xFF1F2935);

  static const border = Color(0xFF243040);
  static const borderStrong = Color(0xFF33465C);

  // Brand
  static const gold = Color(0xFFFFC857);
  static const green = Color(0xFF4CAF50);

  // Severity — shared by the scanner, the posture card and finding chips so a
  // colour always means the same thing.
  static const critical = Color(0xFFFF4D5E);
  static const high = Color(0xFFFF8A3D);
  static const medium = Color(0xFFFFC857);
  static const low = Color(0xFF4FC3F7);
  static const safe = Color(0xFF4CAF50);

  // Text
  static const textPrimary = Color(0xFFE8EDF2);
  static const textSecondary = Color(0xFF94A3B4);
  static const textMuted = Color(0xFF5F6E7E);

  static Color severity(String sev) {
    switch (sev.toLowerCase()) {
      case 'critical':
        return critical;
      case 'high':
        return high;
      case 'medium':
        return medium;
      case 'low':
        return low;
      default:
        return safe;
    }
  }
}

class AppSpacing {
  /// Height of the floating glass tab bar itself. Screens must ALSO add the
  /// device's own bottom inset — see [bottomClearance]. Getting that wrong is
  /// what put the tab bar under the system navigation bar.
  static const navBarClearance = 86.0;

  /// Total bottom padding a scrollable needs: tab bar + system navigation.
  static double bottomClearance(BuildContext context) =>
      navBarClearance + MediaQuery.of(context).padding.bottom;

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        secondary: AppColors.green,
        surface: AppColors.surface,
        error: AppColors.critical,
        onPrimary: Color(0xFF1A1200),
        onSurface: AppColors.textPrimary,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.gold.withOpacity(0.16),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.gold : AppColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? AppColors.gold : AppColors.textMuted,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: const Color(0xFF1A1200),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  /// Monospace, for codes and technical identifiers.
  static TextStyle mono({double size = 12, Color? color, FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        color: color ?? AppColors.textSecondary,
        fontWeight: weight ?? FontWeight.w400,
      );

  /// Small all-caps section label.
  static TextStyle label({Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: color ?? AppColors.textMuted,
      );
}
