part of '../main.dart';

/// الشريط السفلي: الرئيسية · الأصدقاء · + · صندوق الوارد · الملف الشخصي
class Shell extends StatefulWidget {
  const Shell({super.key});
  static final tab = ValueNotifier<int>(0);
  static final inboxBadge = ValueNotifier<int>(0);
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Timer? _badgeT, _useT;
  final _built = <int>{0};

  @override
  void initState() {
    super.initState();
    Me.rev.addListener(_refreshBadge);
    Me.rev.addListener(_checkOnboard);
    _refreshBadge();
    _badgeT = Timer.periodic(const Duration(minutes: 2), (_) => _refreshBadge());
    _useT = Timer.periodic(const Duration(minutes: 1), (_) => _countUse());
  }

  /// «الوقت والرفاهية»: يعدّ دقائق الاستخدام اليومية ويذكّر مرة عند بلوغ الحد
  void _countUse() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final key = 'use_${now.year}_${now.month}_${now.day}';
    final m = (Prefs.p.getInt(key) ?? 0) + 1;
    Prefs.p.setInt(key, m);
    final limit = Prefs.p.getInt('screen_limit') ?? 0;
    if (limit > 0 && m == limit && mounted) {
      showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('وقت الاستراحة؟', style: E.t(17, w: FontWeight.w700)),
        content: Text('استخدمت ${Cfg.appName} $m دقيقة اليوم. خذ استراحة قصيرة 🌿', style: E.t(14, c: E.ink2)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ));
    }
  }

  @override
  void dispose() {
    Me.rev.removeListener(_refreshBadge);
    Me.rev.removeListener(_checkOnboard);
    _badgeT?.cancel();
    _useT?.cancel();
    super.dispose();
  }

  /// من دخل بغوغل/فيسبوك/آبل يكمل اسم المستخدم وسنة الميلاد والموافقة أولاً
  bool _onboarding = false;
  Future<void> _checkOnboard() async {
    final p = Me.profile;
    if (_onboarding || p == null || p.onboarded || !mounted) return;
    _onboarding = true;
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const OnboardingPage()));
    _onboarding = false;
  }

  Future<void> _refreshBadge() async {
    if (!Me.signedIn) { Shell.inboxBadge.value = 0; return; }
    try {
      final n = await Api.unreadNotifs();
      final convs = await Api.convs();
      Shell.inboxBadge.value = n + convs.fold<int>(0, (a, c) => a + c.unread);
    } catch (_) {}
  }

  Future<void> _go(int i) async {
    HapticFeedback.selectionClick();
    if (i == 2) {
      if (!await Me.ensure(context) || !mounted) return;
      final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PostPage()));
      if (posted == true) Me.refresh();
      return;
    }
    if ((i == 3 || i == 4) && !Me.signedIn) {
      if (!await Me.ensure(context) || !mounted) return;
    }
    setState(() => _built.add(i));
    Shell.tab.value = i;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Shell.tab,
        builder: (_, tab, __) {
          final dark = tab == 0;
          return Scaffold(
            backgroundColor: dark ? Colors.black : Colors.white,
            body: IndexedStack(index: tab == 2 ? 0 : tab, children: [
              FeedPage(active: tab == 0),
              _built.contains(1) ? const FriendsPage() : const SizedBox(),
              const SizedBox(),
              _built.contains(3) ? const InboxPage() : const SizedBox(),
              _built.contains(4) ? const ProfilePage() : const SizedBox(),
            ]),
            bottomNavigationBar: _NavBar(tab: tab, dark: dark, onTap: _go),
          );
        },
      );
}

class _NavBar extends StatelessWidget {
  final int tab;
  final bool dark;
  final ValueChanged<int> onTap;
  const _NavBar({required this.tab, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : E.ink;
    final dim = dark ? Colors.white60 : E.ink3;
    Widget item(int i, IconData on, IconData off, String label, {int badge = 0}) {
      final sel = tab == i;
      return Expanded(
        child: InkResponse(
          onTap: () => onTap(i),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : '$badge'),
              backgroundColor: E.accent,
              child: Icon(sel ? on : off, size: 27, color: sel ? fg : dim),
            ),
            const SizedBox(height: 2),
            Text(label, style: E.t(10.5, w: sel ? FontWeight.w700 : FontWeight.w500, c: sel ? fg : dim)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: dark ? Colors.black : Colors.white,
        border: Border(top: BorderSide(color: dark ? Colors.white12 : E.line, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            item(0, Icons.home_rounded, Icons.home_outlined, 'الرئيسية'),
            item(1, Icons.people_rounded, Icons.people_outline_rounded, 'الأصدقاء'),
            Expanded(child: Center(child: _PlusButton(dark: dark, onTap: () => onTap(2)))),
            ValueListenableBuilder<int>(
              valueListenable: Shell.inboxBadge,
              builder: (_, n, __) => item(3, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'صندوق الوارد', badge: n),
            ),
            item(4, Icons.person_rounded, Icons.person_outline_rounded, 'الملف الشخصي'),
          ]),
        ),
      ),
    );
  }
}

/// زر النشر: كبسولة بلونين على الجانبين
class _PlusButton extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;
  const _PlusButton({required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 50, height: 32,
          child: Stack(children: [
            Positioned(left: 0, top: 0, bottom: 0, width: 44,
                child: DecoratedBox(decoration: BoxDecoration(color: E.accent2, borderRadius: BorderRadius.circular(9)))),
            Positioned(right: 0, top: 0, bottom: 0, width: 44,
                child: DecoratedBox(decoration: BoxDecoration(color: E.accent, borderRadius: BorderRadius.circular(9)))),
            Positioned(left: 3, right: 3, top: 0, bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: dark ? Colors.white : E.ink, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.add_rounded, color: dark ? Colors.black : Colors.white, size: 24),
                )),
          ]),
        ),
      );
}
