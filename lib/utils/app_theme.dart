import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
}

class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
}

class AppBreakpoints {
  static const double compactPhone = 380;
  static const double tablet = 720;
  static const double largeTablet = 1024;

  static bool isCompactPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactPhone;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  static bool isLargeTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= largeTablet;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

  static int productGridCount(BuildContext context, {bool twoPane = false}) {
    final width = MediaQuery.sizeOf(context).width;
    if (twoPane) {
      final catalogWidth = width - 400; // minus cart panel
      if (catalogWidth >= 780) return 4;
      if (catalogWidth >= 520) return 3;
      return 2;
    }
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  static int quickActionGridCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final textScale = textScaleFactor(context, max: 1.6);
    if (width >= 900) return 6;
    if (width >= 600) return 4;
    if (width < 360 && textScale >= 1.3) return 3;
    return 4;
  }

  static double textScaleFactor(BuildContext context, {double max = 1.8}) =>
      MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, max);

  static double scaledExtent(
    BuildContext context, {
    required double fixedHeight,
    required double textHeight,
    double maxScale = 1.8,
  }) =>
      fixedHeight + textHeight * textScaleFactor(context, max: maxScale);

  static Widget buildResponsivePair({
    required Widget first,
    required Widget second,
    double minPairWidth = 420,
    double spacing = 10,
    int firstFlex = 1,
    int secondFlex = 1,
    CrossAxisAlignment rowCrossAxisAlignment = CrossAxisAlignment.start,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final threshold = minPairWidth * textScaleFactor(context, max: 1.35);
        if (constraints.maxWidth < threshold) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(height: spacing),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: rowCrossAxisAlignment,
          children: [
            Expanded(flex: firstFlex, child: first),
            SizedBox(width: spacing),
            Expanded(flex: secondFlex, child: second),
          ],
        );
      },
    );
  }

  static double boundedDialogWidth(BuildContext context, {double maxWidth = 460}) =>
      (MediaQuery.sizeOf(context).width - 80).clamp(200.0, maxWidth);

  static Widget scrollableDialogContent(
    BuildContext context, {
    required Widget child,
    double maxWidth = 460,
  }) {
    final w = boundedDialogWidth(context, maxWidth: maxWidth);
    return SizedBox(
      width: w,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  static Widget spaceBetweenRow(
    Widget left,
    Widget right, {
    double gap = 8,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Flexible(child: right),
      ],
    );
  }
}

class AppTheme {
  static const Color primaryGreen = Color(0xFF0F766E);
  static const Color primaryGreenLight = Color(0xFF14B8A6);
  static const Color primaryGreenSoft = Color(0xFFCCFBF1);
  static const Color darkBg = Color(0xFF0F172A);
  static const Color cardBg = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color textMuted = Color(0xFF64748B);
  static const Color accentOrange = Color(0xFFF97316);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentRedSoft = Color(0xFFFEE2E2);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentIndigo = Color(0xFF6366F1);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color lightGreyBg = Color(0xFFF8FAFC);

  static BoxDecoration cardDecoration({Color? borderColor, double radius = AppRadius.md}) {
    return BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? borderLight),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  static InputDecoration denseInputDecoration({
    String? labelText,
    String? hintText,
    String? prefixText,
    String? suffixText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      suffixText: suffixText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: primaryGreen, width: 1.8),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: accentOrange,
        surface: lightGreyBg,
        error: accentRed,
      ),
      scaffoldBackgroundColor: lightGreyBg,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: borderLight, width: 0.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          side: const BorderSide(color: primaryGreen, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryGreen, width: 1.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        backgroundColor: Colors.white,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
