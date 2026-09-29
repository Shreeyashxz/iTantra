import 'package:flutter/material.dart';

// Offline-first: system fonts only. google_fonts was removed because it
// fetches Inter over HTTP on first run — unacceptable for field/offline use.

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

  // ── Brand Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF448AFF), accentCyan],
  );

  static const LinearGradient emergencyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emergencyRed, Color(0xFFFF6D00)],
  );

  /// Glassmorphic card decoration — translucent frosted-glass effect.
  /// Uses brightness to auto-adapt between dark and light themes.
  static BoxDecoration glassmorphicDecoration(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? Colors.white.withAlpha(10)
          : Colors.white.withAlpha(200),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark
            ? Colors.white.withAlpha(18)
            : Colors.black.withAlpha(10),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 40 : 12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Custom page route with slide+fade transition.
  static Route<T> pageTransition<T>(Widget page, {int durationMs = 300}) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: Duration(milliseconds: durationMs),
    );
  }

  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;

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
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
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
        titleLarge: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        titleSmall: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(fontSize: 12),
        labelLarge: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme = ThemeData.light().textTheme;

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
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFD1E4FF),
        foregroundColor: primaryBlue,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFF001D36),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        titleSmall: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(fontSize: 12),
        labelLarge: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}
