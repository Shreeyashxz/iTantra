import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Palette: Deep Space ISRO theme with high-contrast tactical accents
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color emergencyRed = Color(0xFFD32F2F);
  static const Color emergencyRedContainer = Color(0xFFFFCDD2);
  static const Color telemetryGreen = Color(0xFF00E676);
  static const Color darkBackground = Color(0xFF0A0E17);
  static const Color darkSurface = Color(0xFF131A29);
  static const Color darkSurfaceVariant = Color(0xFF1B2438);

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF448AFF),
        primaryContainer: const Color(0xFF1565C0),
        onPrimary: Colors.white,
        secondary: accentCyan,
        onSecondary: Colors.black,
        error: emergencyRed,
        errorContainer: const Color(0xFF5C0000),
        onErrorContainer: const Color(0xFFFFB4AB),
        surface: darkSurface,
        surfaceContainerHighest: darkSurfaceVariant,
        onSurface: const Color(0xFFE2E8F0),
        onSurfaceVariant: const Color(0xFF94A3B8),
      ),
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurfaceVariant,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 22),
        titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.4),
        bodySmall: GoogleFonts.inter(fontSize: 12),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        primaryContainer: const Color(0xFFD1E4FF),
        onPrimary: Colors.white,
        secondary: const Color(0xFF00838F),
        onSecondary: Colors.white,
        error: emergencyRed,
        errorContainer: emergencyRedContainer,
        surface: Colors.white,
        surfaceContainerHighest: const Color(0xFFF1F5F9),
        onSurface: const Color(0xFF0F172A),
        onSurfaceVariant: const Color(0xFF475569),
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFD1E4FF),
        foregroundColor: primaryBlue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF001D36),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 22),
        titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.4),
        bodySmall: GoogleFonts.inter(fontSize: 12),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}
