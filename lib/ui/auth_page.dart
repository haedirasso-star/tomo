part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  الدخول والتسجيل — مستوحى من تيك توك وإنستغرام
//   SplashIntro   ⇐ الشعار بحركة ناعمة عند الفتح
//   WelcomePage   ⇐ (إنستغرام) الشعار في المنتصف · «إنشاء حساب جديد» · «تسجيل الدخول» · from TO
//   AuthPage      ⇐ (تيك توك) قائمة الطرق: البريد · فيسبوك · غوغل · آبل + تبديل «لديك حساب؟»
//   _SignupFlow   ⇐ (تيك توك) خطوات: تاريخ الميلاد ⇐ البريد وكلمة المرور ⇐ اسم المستخدم
//   _LoginPage    ⇐ البريد/اسم المستخدم + كلمة المرور + نسيت كلمة المرور
// ════════════════════════════════════════════════════════════════════

/// شعار Tomo: الكلمة بتدرّج اللونين
class TomoLogo extends StatelessWidget {
  final double size;
  final bool white;
  const TomoLogo({super.key, this.size = 48, this.white = false});

  @override
  Widget build(BuildContext context) {
    final text = Text('tomo', textDirection: TextDirection.ltr,
        style: GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -size * 0.04, height: 1, color: Colors.white));
    if (white) return text;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => const LinearGradient(colors: [E.accent2, E.accent], begin: Alignment.centerLeft, end: Alignment.centerRight).createShader(r),
      child: text,
    );
  }
}

/// أيقونة مربعة (للإنترو والملف الشخصي): حرف t أبيض على تدرّج
class TomoMark extends StatelessWidget {
  final double size;
  const TomoMark({super.key, this.size = 88});
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(colors: [E.accent2, E.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: E.accent.withOpacity(0.28), blurRadius: size * 0.3, offset: Offset(0, size * 0.1))],
        ),
        alignment: Alignment.center,
        child: Text('t', textDirection: TextDirection.ltr,
            style: GoogleFonts.poppins(fontSize: size * 0.62, fontWeight: FontWeight.w800, color: Colors.white, height: 1.05)),
      );
}

/// الإنترو: الأيقونة تكبر بنعومة ثم «from TO» ثم ينتقل التطبيق
class SplashIntro extends StatefulWidget {
  final Widget next;
  const SplashIntro({super.key, required this.next});
  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      ));
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(children: [
            Center(
              child: AnimatedBuilder(
                animation: _a,
                builder: (_, child) {
                  final t = Curves.easeOutBack.transform(_a.value.clamp(0.0, 1.0));
                  return Opacity(opacity: _a.value.clamp(0.0, 1.0), child: Transform.scale(scale: 0.6 + 0.4 * t, child: child));
                },
                child: const TomoMark(size: 96),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FadeTransition(opacity: CurvedAnimation(parent: _a, curve: const Interval(0.5, 1)), child: const _FromTo()),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// «from TO» أسفل الشاشة (مثل from Meta)
class _FromTo extends StatelessWidget {
  const _FromTo();
  static const bool dark = false;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('from', textDirection: TextDirection.ltr, style: GoogleFonts.poppins(fontSize: 13, color: dark ? Colors.white54 : E.ink3)),
        const SizedBox(height: 2),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(colors: [E.accent2, E.accent]).createShader(r),
          child: Text('TO', textDirection: TextDirection.ltr, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white)),
        ),
      ]);
}

/// شاشة الترحيب (إنستغرام): تظهر عند الفتح لمن لم يسجّل — مع «تخطٍّ» للتصفح كضيف
class WelcomePage extends StatelessWidget {
  final VoidCallback onDone;
  const WelcomePage({super.key, required this.onDone});

  static const _skipKey = 'welcome_skipped_v1';
  static bool get skipped => Prefs.p.getBool(_skipKey) ?? false;

  Future<void> _open(BuildContext context, bool signup) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AuthPage(signup: signup)));
    if (ok == true || Me.signedIn) onDone();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () { Prefs.p.setBool(_skipKey, true); onDone(); },
                    child: Text('تخطٍّ', style: E.t(15, w: FontWeight.w600, c: E.ink2)),
                  ),
                ),
                const Spacer(flex: 3),
                const TomoMark(size: 84),
                const SizedBox(height: 22),
                const TomoLogo(size: 46),
                const SizedBox(height: 12),
                Text('شارك لحظاتك بالفيديو مع العالم', textAlign: TextAlign.center, style: E.t(16, c: E.ink2)),
                const Spacer(flex: 4),
                _WideButton(label: 'إنشاء حساب جديد', primary: true, onTap: () => _open(context, true)),
                const SizedBox(height: 12),
                _WideButton(label: 'تسجيل الدخول', onTap: () => _open(context, false)),
                const SizedBox(height: 26),
                const _FromTo(),
                const SizedBox(height: 14),
              ]),
            ),
          ),
        ),
      );
}

/// زر عريض بزوايا دائرية (إنستغرام)
class _WideButton extends StatelessWidget {
  final String label;
  final bool primary, busy;
  final VoidCallback? onTap;
  const _WideButton({required this.label, this.primary = false, this.busy = false, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity, height: 50,
        child: Material(
          color: primary ? (onTap == null ? E.accent.withOpacity(0.35) : E.accent) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25),
              side: primary ? BorderSide.none : const BorderSide(color: Color(0xFFDBDBDB))),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: primary ? Colors.white : E.ink))
                  : Text(label, style: E.t(15.5, w: FontWeight.w700, c: primary ? Colors.white : E.ink)),
            ),
          ),
        ),
      );
}

/// صفحة الطرق (تيك توك): «سجّل في Tomo» / «سجّل الدخول إلى Tomo»
class AuthPage extends StatefulWidget {
  final bool signup;
  const AuthPage({super.key, this.signup = true});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late bool _signup = widget.signup;
  bool _busy = false;
  String _err = '';

  Future<void> _social(OAuthProvider provider) async {
    setState(() { _err = ''; _busy = true; });
    StreamSubscription<AuthState>? sub;
    try {
      sub = sb.auth.onAuthStateChange.listen((s) async {
        if (s.event == AuthChangeEvent.signedIn && mounted) {
          await sub?.cancel();
          await Me.refresh();
          if (mounted) Navigator.of(context).pop(true);
        }
      });
      final ok = await sb.auth.signInWithOAuth(provider, redirectTo: Cfg.authRedirect, authScreenLaunchMode: LaunchMode.externalApplication);
      if (!ok) throw Exception('تعذّر فتح صفحة الدخول');
    } catch (e) {
      await sub?.cancel();
      if (mounted) setState(() => _err = errText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _email() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _signup ? const _SignupFlow() : const _LoginPage()));
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded, size: 26), onPressed: () => Navigator.pop(context)),
          actions: [IconButton(icon: const Icon(Icons.help_outline_rounded), onPressed: () => LegalPage.open(context, terms: true))],
        ),
        body: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(28, 12, 28, 20), children: [
              Text(_signup ? 'سجّل في ${Cfg.appName}' : 'سجّل الدخول إلى ${Cfg.appName}',
                  textAlign: TextAlign.center, style: E.t(25, w: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                _signup
                    ? 'أنشئ ملفاً شخصياً، وتابع حسابات أخرى، وصوّر مقاطع الفيديو الخاصة بك، والمزيد.'
                    : 'أدِر حسابك، وتحقق من الإشعارات، وعلّق على مقاطع الفيديو، والمزيد.',
                textAlign: TextAlign.center, style: E.t(14.5, c: E.ink3, h: 1.5),
              ),
              const SizedBox(height: 30),
              _Method(icon: Icons.person_outline_rounded, label: _signup ? 'استخدام البريد الإلكتروني' : 'استخدام البريد الإلكتروني / اسم المستخدم',
                  onTap: _busy ? null : _email),
              _Method(iconWidget: const _BrandIcon('f', Color(0xFF1877F2)), label: 'المتابعة باستخدام Facebook',
                  onTap: _busy ? null : () => _social(OAuthProvider.facebook)),
              _Method(iconWidget: const _GoogleG(), label: 'المتابعة باستخدام Google',
                  onTap: _busy ? null : () => _social(OAuthProvider.google)),
              if (io.Platform.isIOS)
                _Method(icon: Icons.apple_rounded, label: 'المتابعة باستخدام Apple', onTap: _busy ? null : () => _social(OAuthProvider.apple)),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: Loading()),
              if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err, textAlign: TextAlign.center, style: E.t(13.5, c: E.accent))),
            ]),
          ),
          if (_signup)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
              child: Text.rich(
                TextSpan(style: E.t(12, c: E.ink3, h: 1.6), children: [
                  const TextSpan(text: 'بالمتابعة، فإنك توافق على '),
                  TextSpan(text: 'شروط الخدمة', style: E.t(12, w: FontWeight.w700, c: E.ink),
                      recognizer: TapGestureRecognizer()..onTap = () => LegalPage.open(context, terms: true)),
                  TextSpan(text: ' الخاصة بنا وتقر بأنك قد قرأت '),
                  TextSpan(text: 'سياسة الخصوصية', style: E.t(12, w: FontWeight.w700, c: E.ink),
                      recognizer: TapGestureRecognizer()..onTap = () => LegalPage.open(context)),
                  const TextSpan(text: ' لمعرفة كيفية جمعنا لبياناتك واستخدامها ومشاركتها.'),
                ]),
                textAlign: TextAlign.center,
              ),
            ),
          Container(
            width: double.infinity,
            color: const Color(0xFFF8F8F8),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_signup ? 'هل لديك حساب؟ ' : 'ليس لديك حساب؟ ', style: E.t(14.5, c: E.ink)),
                  GestureDetector(
                    onTap: () => setState(() { _signup = !_signup; _err = ''; }),
                    child: Text(_signup ? 'تسجيل الدخول' : 'التسجيل', style: E.t(14.5, w: FontWeight.w800, c: E.accent)),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );
}

/// سطر طريقة دخول بإطار رمادي — الأيقونة في البداية والنص في المنتصف (تيك توك)
class _Method extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback? onTap;
  const _Method({this.icon, this.iconWidget, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: Color(0xFFE3E3E4))),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Row(children: [
                const SizedBox(width: 14),
                SizedBox(width: 24, child: Center(child: iconWidget ?? Icon(icon, size: 24, color: E.ink))),
                Expanded(child: Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: E.t(15, w: FontWeight.w600))),
                const SizedBox(width: 38),
              ]),
            ),
          ),
        ),
      );
}

class _BrandIcon extends StatelessWidget {
  final String letter;
  final Color color;
  const _BrandIcon(this.letter, this.color);
  @override
  Widget build(BuildContext context) => Container(
        width: 22, height: 22, decoration: BoxDecoration(color: color, shape: BoxShape.circle), alignment: Alignment.bottomCenter,
        child: Text(letter, textDirection: TextDirection.ltr, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15)),
      );
}

/// حرف G بألوان غوغل الأربعة
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => const SweepGradient(
          colors: [Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF4285F4), Color(0xFFEA4335)],
          stops: [0.0, 0.3, 0.55, 0.8, 1.0],
        ).createShader(r),
        child: Text('G', textDirection: TextDirection.ltr, style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
      );
}

/// شريط خطوات رفيع أعلى صفحات التسجيل
Widget _stepTitle(String t, [String sub = '']) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: E.t(23, w: FontWeight.w800)),
      if (sub.isNotEmpty) ...[const SizedBox(height: 6), Text(sub, style: E.t(14, c: E.ink3, h: 1.5))],
      const SizedBox(height: 22),
    ]);

InputDecoration _underline(String hint, {Widget? suffix, String? prefix}) => InputDecoration(
      hintText: hint, filled: false, prefixText: prefix, suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE3E3E4))),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: E.ink, width: 1.4)),
      border: const UnderlineInputBorder(),
    );

/// التسجيل بالبريد بخطوات تيك توك: تاريخ الميلاد ⇐ البريد وكلمة المرور ⇐ اسم المستخدم
class _SignupFlow extends StatefulWidget {
  const _SignupFlow();
  @override
  State<_SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<_SignupFlow> {
  final _pc = PageController();
  int _step = 0;
  DateTime? _birth;
  final _email = TextEditingController(), _pass = TextEditingController(), _user = TextEditingController(), _name = TextEditingController();
  bool _hide = true, _busy = false, _agree = false;
  String _err = '';
  bool? _userFree;
  Timer? _deb;

  @override
  void dispose() {
    for (final c in [_email, _pass, _user, _name]) { c.dispose(); }
    _pc.dispose();
    _deb?.cancel();
    super.dispose();
  }

  int get _age {
    final b = _birth;
    if (b == null) return 0;
    final n = DateTime.now();
    return n.year - b.year - ((n.month < b.month || (n.month == b.month && n.day < b.day)) ? 1 : 0);
  }

  bool get _emailOk => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());
  bool get _lenOk => _pass.text.length >= 8;
  bool get _mixOk => RegExp(r'[A-Za-z]').hasMatch(_pass.text) && RegExp(r'[0-9]').hasMatch(_pass.text);
  bool get _userOk => RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(_user.text.trim().toLowerCase());

  void _go(int s) {
    FocusScope.of(context).unfocus();
    setState(() { _step = s; _err = ''; });
    _pc.animateToPage(s, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _back() => _step == 0 ? Navigator.pop(context) : _go(_step - 1);

  void _checkUser(String v) {
    _deb?.cancel();
    setState(() => _userFree = null);
    if (!_userOk) return;
    _deb = Timer(const Duration(milliseconds: 450), () async {
      try {
        final p = await Api.byUsername(v.trim());
        if (mounted && _user.text.trim() == v.trim()) setState(() => _userFree = p == null);
      } catch (_) {}
    });
  }

  Future<void> _create() async {
    if (!_userOk) { setState(() => _err = 'اسم المستخدم: 3–24 حرفاً إنجليزياً صغيراً أو أرقاماً أو _ .'); return; }
    if (_userFree == false) { setState(() => _err = 'اسم المستخدم محجوز — جرّب غيره'); return; }
    if (!_agree) { setState(() => _err = 'وافق على الشروط وسياسة الخصوصية للمتابعة'); return; }
    setState(() { _busy = true; _err = ''; });
    final email = _email.text.trim();
    try {
      final r = await sb.auth.signUp(email: email, password: _pass.text, data: {
        'username': _user.text.trim().toLowerCase(), 'name': _name.text.trim(), 'birth_year': '${_birth!.year}',
      });
      if (r.session == null) {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CheckEmailPage(email: email)));
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      await Me.refresh();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e); });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (did, _) { if (!did) _back(); },
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
            title: Text('التسجيل', style: E.t(16.5, w: FontWeight.w700)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (_step + 1) / 3), duration: const Duration(milliseconds: 280),
                builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 2.5, color: E.ink, backgroundColor: E.soft),
              ),
            ),
          ),
          body: PageView(controller: _pc, physics: const NeverScrollableScrollPhysics(), children: [_birthStep(), _credStep(), _userStep()]),
        ),
      );

  Widget _birthStep() {
    final now = DateTime.now();
    final b = _birth;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepTitle('ما تاريخ ميلادك؟', 'لن يظهر تاريخ ميلادك للعامة. نستخدمه فقط لحماية الحسابات وتقديم تجربة مناسبة لعمرك.'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE3E3E4)))),
          child: Text(b == null ? 'تاريخ الميلاد' : '${b.day} / ${b.month} / ${b.year}',
              style: E.t(17, w: b == null ? FontWeight.w400 : FontWeight.w700, c: b == null ? E.ink3 : E.ink)),
        ),
        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err, style: E.t(13, c: E.accent))),
        const Spacer(),
        SizedBox(
          height: 200,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: DateTime(now.year - 18, now.month, math.min(now.day, 28)),
              minimumDate: DateTime(now.year - 100),
              maximumDate: now,
              dateOrder: DatePickerDateOrder.dmy,
              onDateTimeChanged: (d) => setState(() { _birth = d; _err = ''; }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _WideButton(label: 'التالي', primary: true, onTap: b == null ? null : () {
          if (_age < 13) { setState(() => _err = 'عذراً، يجب أن يكون عمرك 13 سنة أو أكثر لاستخدام ${Cfg.appName}'); return; }
          _go(1);
        }),
      ]),
    );
  }

  Widget _credStep() => ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 16), children: [
        _stepTitle('البريد الإلكتروني وكلمة المرور', 'سنرسل رابط تأكيد إلى بريدك لحماية حسابك.'),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, autocorrect: false,
            onChanged: (_) => setState(() {}), decoration: _underline('البريد الإلكتروني')),
        const SizedBox(height: 18),
        TextField(controller: _pass, obscureText: _hide, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}),
            decoration: _underline('كلمة المرور', suffix: IconButton(
                icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: E.ink3),
                onPressed: () => setState(() => _hide = !_hide)))),
        const SizedBox(height: 16),
        Text('يجب أن تحتوي كلمة المرور على:', style: E.t(13.5, w: FontWeight.w700)),
        const SizedBox(height: 8),
        _rule('8 أحرف على الأقل', _lenOk),
        _rule('حروف وأرقام', _mixOk),
        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err, style: E.t(13, c: E.accent))),
        const SizedBox(height: 28),
        _WideButton(label: 'التالي', primary: true, onTap: _emailOk && _lenOk && _mixOk ? () => _go(2) : null),
      ]);

  Widget _rule(String t, bool ok) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: ok ? const Color(0xFF16A34A) : E.ink3),
          const SizedBox(width: 8),
          Text(t, style: E.t(13.5, c: ok ? E.ink : E.ink3)),
        ]),
      );

  Widget _userStep() => ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 16), children: [
        _stepTitle('أنشئ اسم مستخدم', 'يمكنك تغييره لاحقاً في أي وقت.'),
        TextField(
          controller: _user, textDirection: TextDirection.ltr, autocorrect: false,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')), LengthLimitingTextInputFormatter(24)],
          onChanged: _checkUser,
          decoration: _underline('اسم المستخدم', prefix: '@ ', suffix: _user.text.isEmpty ? null : Padding(
            padding: const EdgeInsets.all(12),
            child: _userFree == null
                ? (_userOk ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const SizedBox(width: 16))
                : Icon(_userFree! ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 20,
                    color: _userFree! ? const Color(0xFF16A34A) : E.accent),
          )),
        ),
        if (_userFree == false) Padding(padding: const EdgeInsets.only(top: 6), child: Text('هذا الاسم محجوز', style: E.t(12.5, c: E.accent))),
        const SizedBox(height: 18),
        TextField(controller: _name, maxLength: 40, decoration: _underline('الاسم الظاهر (اختياري)').copyWith(counterText: '')),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _agree, onChanged: (v) => setState(() => _agree = v == true),
          contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: E.ink,
          title: Text.rich(TextSpan(style: E.t(13, c: E.ink2), children: [
            const TextSpan(text: 'أوافق على '),
            TextSpan(text: 'شروط الخدمة', style: E.t(13, w: FontWeight.w700),
                recognizer: TapGestureRecognizer()..onTap = () => LegalPage.open(context, terms: true)),
            const TextSpan(text: ' و'),
            TextSpan(text: 'إرشادات المجتمع', style: E.t(13, w: FontWeight.w700),
                recognizer: TapGestureRecognizer()..onTap = () => LegalPage.open(context, guidelines: true)),
            const TextSpan(text: ' و'),
            TextSpan(text: 'سياسة الخصوصية', style: E.t(13, w: FontWeight.w700),
                recognizer: TapGestureRecognizer()..onTap = () => LegalPage.open(context)),
          ])),
        ),
        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err, style: E.t(13, c: E.accent))),
        const SizedBox(height: 20),
        _WideButton(label: 'تسجيل', primary: true, busy: _busy, onTap: _userOk && _userFree != false ? _create : null),
      ]);
}

/// بعد التسجيل: تحقق من بريدك (مثل إنستغرام)
class _CheckEmailPage extends StatelessWidget {
  final String email;
  const _CheckEmailPage({required this.email});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const SizedBox(height: 30),
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: E.ink, width: 2)),
              child: const Icon(Icons.mark_email_unread_outlined, size: 46, color: E.ink),
            ),
            const SizedBox(height: 24),
            Text('تحقق من بريدك', style: E.t(23, w: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('أرسلنا رابط تأكيد إلى\n$email\nافتحه لتفعيل حسابك ثم سجّل الدخول.', textAlign: TextAlign.center, style: E.t(14.5, c: E.ink2, h: 1.6)),
            const Spacer(),
            _WideButton(label: 'حسناً، تسجيل الدخول', primary: true, onTap: () => Navigator.pop(context)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                try {
                  await sb.auth.resend(type: OtpType.signup, email: email);
                  if (context.mounted) toast(context, 'أُعيد الإرسال');
                } catch (e) {
                  if (context.mounted) toast(context, errText(e));
                }
              },
              child: Text('لم يصلك؟ إعادة الإرسال', style: E.t(14, w: FontWeight.w600, c: E.ink2)),
            ),
          ]),
        ),
      );
}

/// تسجيل الدخول بالبريد أو اسم المستخدم
class _LoginPage extends StatefulWidget {
  const _LoginPage();
  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _id = TextEditingController(), _pass = TextEditingController();
  bool _hide = true, _busy = false;
  String _err = '';

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final id = _id.text.trim();
    if (id.isEmpty || _pass.text.isEmpty) return;
    setState(() { _busy = true; _err = ''; });
    try {
      var email = id;
      if (!id.contains('@')) {
        // اسم المستخدم ⇐ البريد (عبر دالة آمنة لا تكشف البريد إلا لمن يعرف كلمة المرور الصحيحة)
        final r = await sb.rpc('login_email', params: {'p_username': id.replaceAll('@', '').toLowerCase(), 'p_password': _pass.text});
        if (r == null || '$r'.isEmpty) throw Exception('البريد/اسم المستخدم أو كلمة المرور غير صحيحة');
        email = '$r';
      }
      await sb.auth.signInWithPassword(email: email, password: _pass.text);
      await Me.refresh();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e).contains('غير صحيحة') || e is AuthException ? 'البريد/اسم المستخدم أو كلمة المرور غير صحيحة' : errText(e); });
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: _id.text.contains('@') ? _id.text.trim() : '');
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: Colors.white, showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('إعادة تعيين كلمة المرور', style: E.t(19, w: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('اكتب بريدك وسنرسل لك رابطاً لتعيين كلمة مرور جديدة.', style: E.t(13.5, c: E.ink3)),
          const SizedBox(height: 16),
          TextField(controller: c, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: _underline('البريد الإلكتروني')),
          const SizedBox(height: 22),
          _WideButton(label: 'إرسال الرابط', primary: true, onTap: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (ok != true || !c.text.contains('@')) return;
    try {
      await sb.auth.resetPasswordForEmail(c.text.trim());
      if (mounted) toast(context, 'إن كان البريد مسجّلاً سيصلك الرابط خلال دقائق');
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text('تسجيل الدخول', style: E.t(16.5, w: FontWeight.w700))),
        body: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 16), children: [
          TextField(controller: _id, textDirection: TextDirection.ltr, autocorrect: false, keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}), decoration: _underline('البريد الإلكتروني أو اسم المستخدم')),
          const SizedBox(height: 18),
          TextField(controller: _pass, obscureText: _hide, textDirection: TextDirection.ltr, onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _login(),
              decoration: _underline('كلمة المرور', suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: E.ink3),
                  onPressed: () => setState(() => _hide = !_hide)))),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: _forgot, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                child: Text('هل نسيت كلمة المرور؟', style: E.t(13.5, w: FontWeight.w700))),
          ),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_err, style: E.t(13, c: E.accent))),
          const SizedBox(height: 10),
          _WideButton(label: 'تسجيل الدخول', primary: true, busy: _busy,
              onTap: _id.text.trim().isNotEmpty && _pass.text.isNotEmpty ? _login : null),
        ]),
      );
}
