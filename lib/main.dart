// ════════════════════════════════════════════════════════════════════
//  Tomo — منصة فيديو قصير اجتماعية (من TO)
//
//  الرئيسية (فيديوهات «لك» و«أتابعهم») · الأصدقاء · + نشر · صندوق الوارد · الملف الشخصي
//  الخادم: Supabase مستقل (المصادقة · قاعدة البيانات · التخزين · الرسائل الفورية)
// ════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoDatePickerMode, DatePickerDateOrder;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'core/config.dart';
part 'core/theme.dart';
part 'core/util.dart';
part 'data/models.dart';
part 'data/api.dart';
part 'data/session.dart';
part 'data/trk.dart';
part 'data/video_cache.dart';
part 'data/promo.dart';
part 'data/secure_storage.dart';
part 'ui/widgets.dart';
part 'ui/shell.dart';
part 'ui/auth_page.dart';
part 'ui/feed/feed_page.dart';
part 'ui/feed/video_view.dart';
part 'ui/feed/comments_sheet.dart';
part 'ui/friends_page.dart';
part 'ui/post_page.dart';
part 'ui/inbox/inbox_page.dart';
part 'ui/inbox/chat_page.dart';
part 'ui/profile/profile_page.dart';
part 'ui/profile/edit_profile_page.dart';
part 'ui/profile/settings_page.dart';
part 'ui/profile/user_list_page.dart';
part 'ui/video_list_page.dart';
part 'ui/legal_page.dart';
part 'ui/promote_pages.dart';
part 'ui/admin_page.dart';
part 'ui/onboarding_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  E.resolve();
  if (Cfg.ready) {
    await Supabase.initialize(
      url: Cfg.supabaseUrl,
      anonKey: Cfg.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureLocalStorage(), authFlowType: AuthFlowType.pkce),
    );
    Me.init();
    Trk.init();
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const TomoApp());
}

class TomoApp extends StatefulWidget {
  const TomoApp({super.key});
  @override
  State<TomoApp> createState() => _TomoAppState();
}

/// يتابع وضع الهاتف (ليلي/نهاري) واختيار المستخدم، ويعيد رسم كل الشاشات فوراً
class _TomoAppState extends State<TomoApp> with WidgetsBindingObserver {
  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    E.mode.addListener(_apply);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    E.mode.removeListener(_apply);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _apply();

  void _apply() {
    final was = E.dark;
    E.resolve();
    if (was == E.dark || !mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _nav.currentContext;
      if (c != null) E.repaintAll(c);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _nav,
        title: Cfg.appName,
        debugShowCheckedModeBanner: false,
        theme: E.theme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Cfg.ready ? const SplashIntro(next: _Root()) : const _SetupNeeded(),
      );
}

/// بعد الإنترو: شاشة الترحيب لمن لم يسجّل (ولم يتخطَّها) — وإلا التطبيق مباشرة
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late bool _welcome = !Me.signedIn && !WelcomePage.skipped;
  bool _was = Me.signedIn;

  @override
  void initState() {
    super.initState();
    Me.rev.addListener(_auth);
  }

  @override
  void dispose() {
    Me.rev.removeListener(_auth);
    super.dispose();
  }

  /// تسجيل الخروج أو حذف الحساب ⇐ العودة لشاشة الترحيب
  void _auth() {
    final now = Me.signedIn;
    if (_was && !now && mounted) {
      Prefs.p.remove('welcome_skipped_v1');
      Shell.tab.value = 0;
      setState(() => _welcome = true);
    }
    _was = now;
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        child: _welcome ? WelcomePage(key: const ValueKey('w'), onDone: () => setState(() => _welcome = false)) : const Shell(key: ValueKey('s')),
      );
}

/// يظهر فقط إذا بُني التطبيق بلا مفاتيح Supabase (--dart-define)
class _SetupNeeded extends StatelessWidget {
  const _SetupNeeded();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('${Cfg.appName}\n\nلم تُضبط مفاتيح الخادم.\nابنِ التطبيق مع SUPABASE_URL و SUPABASE_ANON_KEY.',
                textAlign: TextAlign.center, style: E.t(16, w: FontWeight.w700)),
          ),
        ),
      );
}
