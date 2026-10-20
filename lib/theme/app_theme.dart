import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppColors {
  // Primary Civic Palette (WCAG AA Compliant)
  static const Color greenDark = Color(0xFF0F5132); // Deep Forest Green
  static const Color green = Color(0xFF166534); // Primary Accent Green
  static const Color greenSoft = Color(0xFFE8F5E9); // Subtle container tint
  static const Color greenSurface = Color(0xFFF4F9F5);

  // High-Contrast Neutral Surfaces
  static const Color background = Color(0xFFF8FAFC); // Clean off-white canvas
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE2E8F0); // Hairline card border
  static const Color borderLight = Color(0xFFF1F5F9);

  // Typography Tokens
  static const Color text = Color(0xFF0F172A); // Slate 900 for titles
  static const Color textSecondary = Color(0xFF334155); // Slate 700 for body
  static const Color muted = Color(0xFF64748B); // Slate 500 for captions

  // Emergency Semantic Token (High contrast red only for genuine SOS)
  static const Color danger = Color(0xFFB91C1C); // Red 700
  static const Color dangerSoft = Color(0xFFFEE2E2);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.green,
        primary: AppColors.green,
        onPrimary: Colors.white,
        surface: AppColors.card,
        onSurface: AppColors.text,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: kIsWeb
          ? '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto'
          : null,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}

/// Responsive wrapper that centers and constrains layouts on iOS Web & Tablets
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
