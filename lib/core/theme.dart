part of '../main.dart';

/// هوية Tomo: أبيض وأسود نظيف + لون مميّز واحد
class E {
  E._();
  static const accent = Color(0xFFFF3B5C);
  static const accent2 = Color(0xFF7C5CFF);
  static const ink = Color(0xFF161823);
  static const ink2 = Color(0xFF57585F);
  static const ink3 = Color(0xFF8A8B91);
  static const line = Color(0xFFE8E8EA);
  static const bg = Colors.white;
  static const soft = Color(0xFFF1F1F2);
  static const online = Color(0xFF20D5EC);

  static TextStyle t(double size, {FontWeight w = FontWeight.w500, Color c = ink, double? h}) =>
      GoogleFonts.ibmPlexSansArabic(fontSize: size, fontWeight: w, color: c, height: h);

  static ThemeData theme() {
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: accent, brightness: Brightness.light);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: bg, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: true,
        titleTextStyle: t(17, w: FontWeight.w700),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
      dividerColor: line,
      splashFactory: InkSparkle.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: soft,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: t(14, c: ink3),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: ink, contentTextStyle: t(14, c: Colors.white)),
    );
  }
}
