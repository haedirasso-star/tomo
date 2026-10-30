part of '../main.dart';

/// المستخدم الحالي وملفه الشخصي — أي شاشة تستمع لـ Me.rev لتتحدث عند الدخول/الخروج/التعديل
class Me {
  Me._();
  static final rev = ValueNotifier<int>(0);
  static Profile? profile;
  static bool get signedIn => sb.auth.currentUser != null;

  static void init() {
    sb.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        profile = null;
        rev.value++;
      } else if (data.session != null) {
        unawaited(refresh());
      }
    });
    if (signedIn) unawaited(refresh());
  }

  static Future<void> refresh() async {
    final id = myId;
    if (id == null) return;
    try {
      profile = await Api.profile(id);
    } catch (_) {}
    rev.value++;
  }

  /// يفتح صفحة الدخول إن لم يكن مسجلاً — ويعيد true إن أصبح مسجلاً
  static Future<bool> ensure(BuildContext context) async {
    if (signedIn) return true;
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const AuthPage()));
    return signedIn;
  }
}
