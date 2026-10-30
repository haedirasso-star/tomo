part of '../main.dart';

/// هوية Tomo: أبيض وأسود نظيف + لون مميّز واحد — مع الوضع الليلي (تلقائي · فاتح · داكن)
class E {
  E._();
  static const accent = Color(0xFFFF3B5C);
  static const accent2 = Color(0xFF7C5CFF);
  static const online = Color(0xFF20D5EC);

  // ── المظهر ─────────────────────────────────────────────────────────
  /// 'system' يتبع الهاتف · 'light' · 'dark'
  static final mode = ValueNotifier<String>(Prefs.p.getString('theme_mode') ?? 'system');
  static bool dark = false;

  static void resolve() {
    final sys = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    dark = mode.value == 'dark' || (mode.value == 'system' && sys);
  }

  static Future<void> setMode(String m) async {
    await Prefs.p.setString('theme_mode', m);
    mode.value = m;
  }

  // ── الألوان (تتبدل حسب الوضع) ───────────────────────────────────────
  static Color get ink => dark ? const Color(0xFFF1F1F2) : const Color(0xFF161823);
  static Color get ink2 => dark ? const Color(0xFFB9BAC0) : const Color(0xFF57585F);
  static Color get ink3 => dark ? const Color(0xFF8A8B91) : const Color(0xFF8A8B91);
  static Color get line => dark ? const Color(0xFF2C2C30) : const Color(0xFFE8E8EA);
  static Color get bg => dark ? const Color(0xFF000000) : Colors.white;
  /// بطاقات وأوراق سفلية
  static Color get card => dark ? const Color(0xFF161618) : Colors.white;
  /// خلفية صفحات الإعدادات المجمّعة
  static Color get page => dark ? const Color(0xFF000000) : const Color(0xFFF6F6F7);
  static Color get soft => dark ? const Color(0xFF232326) : const Color(0xFFF1F1F2);
  static Color get border => dark ? const Color(0xFF3A3A3F) : const Color(0xFFDBDBDB);

  static TextStyle t(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
      GoogleFonts.ibmPlexSansArabic(fontSize: size, fontWeight: w, color: c ?? ink, height: h);

  static ThemeData theme() {
    final b = dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: accent, brightness: b);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: bg, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: true,
        titleTextStyle: t(17, w: FontWeight.w700),
        systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
      ),
      dividerColor: line,
      dividerTheme: DividerThemeData(color: line),
      listTileTheme: ListTileThemeData(iconColor: ink, textColor: ink),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      drawerTheme: DrawerThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent),
      splashFactory: InkSparkle.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: soft,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: t(14, c: ink3),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: dark ? const Color(0xFF2C2C30) : const Color(0xFF161823),
          contentTextStyle: t(14, c: Colors.white)),
    );
  }

  /// يعيد رسم كل الشاشات المفتوحة بالألوان الجديدة (بدون فقدان مكانك في التطبيق)
  static void repaintAll(BuildContext context) {
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }
    (context as Element).visitChildren(rebuild);
  }
}
