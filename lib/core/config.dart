part of '../main.dart';

/// مفاتيح الخادم تُمرَّر وقت البناء (لا تُكتب في الكود):
///   flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=...
/// مفتاح anon عام بطبيعته (الحماية في سياسات RLS في قاعدة البيانات)، لكن لا نضع service_role أبداً في التطبيق.
class Cfg {
  Cfg._();
  /// الاسم التجاري (يتغيّر من هنا ومن البناء فقط)
  static const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Tomo');
  static const version = '1.0.0';
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://tomo.app');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@tomo.app');
  /// رابط العودة بعد الدخول بغوغل/فيسبوك/آبل (يُسجَّل في Supabase ← Auth ← URL Configuration)
  static const authScheme = String.fromEnvironment('AUTH_SCHEME', defaultValue: 'app.tomo');
  static String get authRedirect => '$authScheme://login-callback';
  static bool get ready => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// حدود النشر
  static const maxVideoSeconds = 180;
  static const maxVideoBytes = 200 * 1024 * 1024;
}

/// تفضيلات محلية بسيطة
class Prefs {
  Prefs._();
  static late SharedPreferences p;
  static Future<void> init() async => p = await SharedPreferences.getInstance();
}
