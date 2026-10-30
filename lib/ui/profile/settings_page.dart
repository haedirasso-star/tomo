part of '../../main.dart';

/// الإعدادات والخصوصية
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Profile? get p => Me.profile;

  Future<void> _set(Map<String, dynamic> v) async {
    try {
      await Api.updateProfile(v);
      await Me.refresh();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  void _go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  Future<void> _dm() async {
    final r = await sheetMenu<String>(context, [
      (Icons.public_rounded, 'الجميع', 'everyone', false),
      (Icons.people_outline_rounded, 'الأصدقاء فقط (متابعة متبادلة)', 'friends', false),
      (Icons.block_rounded, 'لا أحد', 'none', false),
    ]);
    if (r != null) await _set({'dm': r});
  }

  Future<void> _wellbeing() async {
    const opts = [0, 30, 60, 90, 120];
    final cur = Prefs.p.getInt('screen_limit') ?? 0;
    final r = await sheetMenu<int>(context, [
      for (final m in opts) (m == cur ? Icons.check_rounded : Icons.timer_outlined, m == 0 ? 'بلا تذكير' : 'ذكّرني بعد $m دقيقة يومياً', m, false),
    ]);
    if (r != null) {
      await Prefs.p.setInt('screen_limit', r);
      if (mounted) toast(context, r == 0 ? 'أُوقف التذكير' : 'سنذكّرك بعد $r دقيقة من الاستخدام اليومي');
    }
  }

  Future<void> _theme() async {
    final r = await sheetMenu<String>(context, [
      (Icons.brightness_auto_outlined, 'تلقائي (حسب الهاتف)', 'system', E.mode.value == 'system'),
      (Icons.light_mode_outlined, 'فاتح', 'light', E.mode.value == 'light'),
      (Icons.dark_mode_outlined, 'داكن (الوضع الليلي)', 'dark', E.mode.value == 'dark'),
    ]);
    if (r != null) {
      await E.setMode(r);
      if (mounted) setState(() {});
    }
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'تسجيل الخروج؟', '', ok: 'خروج')) return;
    await Trk.flush();
    await sb.auth.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      Shell.tab.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = sb.auth.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: E.page,
      appBar: AppBar(backgroundColor: E.page, title: const Text('الإعدادات والخصوصية')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 30), children: [
        _group('النشاط', [
          _item(Icons.video_settings_outlined, 'إدارة المنشورات', () => _go(const ManagePostsPage())),
          _item(Icons.notifications_none_rounded, 'الإشعارات', () => _go(const ActivityPage())),
          _item(Icons.hourglass_bottom_rounded, 'الوقت والرفاهية', _wellbeing),
        ]),
        _group('الحساب', [
          _item(Icons.person_outline_rounded, 'الحساب', () => _go(const AccountPage()), trailing: email),
          _item(Icons.shield_outlined, 'الأمان والحظر', () => _go(const BlockedPage())),
          _item(Icons.insights_rounded, 'التحليلات', () => _go(const AnalyticsPage())),
          _item(Icons.local_fire_department_outlined, 'ترويجاتي', () => _go(const MyPromosPage())),
          _item(Icons.ios_share_rounded, 'مشاركة الملف الشخصي', () {
            if (p != null) Share.share('تابعني على ${Cfg.appName}: ${Cfg.siteUrl}/@${p!.username}');
          }),
        ]),
        if (p?.staff == true)
          _group('الإدارة', [
            _item(Icons.admin_panel_settings_outlined, 'لوحة الإدارة', () => _go(const AdminPage())),
          ]),
        _group('الظهور', [
          _switch(Icons.lock_outline_rounded, 'حساب خاص', 'فيديوهاتك لأصدقائك فقط', p?.private ?? false, (v) => _set({'private': v})),
          _item(Icons.mail_outline_rounded, 'من يمكنه مراسلتي', _dm,
              trailing: const {'everyone': 'الجميع', 'friends': 'الأصدقاء', 'none': 'لا أحد'}[p?.dm ?? 'friends'] ?? ''),
        ]),
        _group('العرض', [
          _item(E.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, 'المظهر', _theme,
              trailing: const {'system': 'تلقائي', 'light': 'فاتح', 'dark': 'داكن'}[E.mode.value] ?? ''),
        ]),
        _group('الذاكرة والبيانات', [
          _item(Icons.cleaning_services_outlined, 'مسح الكاش', () async {
            await VideoCache.clear();
            PaintingBinding.instance.imageCache.clear();
            if (mounted) toast(context, 'تم مسح الكاش');
          }),
        ]),
        _group('الدعم والقانوني', [
          _item(Icons.support_agent_rounded, 'الإبلاغ عن مشكلة', () => launchUrl(Uri.parse('mailto:${Cfg.supportEmail}?subject=${Cfg.appName}'))),
          _item(Icons.rule_rounded, 'إرشادات المجتمع', () => LegalPage.open(context, guidelines: true)),
          _item(Icons.description_outlined, 'شروط الاستخدام', () => LegalPage.open(context, terms: true)),
          _item(Icons.privacy_tip_outlined, 'سياسة الخصوصية', () => LegalPage.open(context, terms: false)),
        ]),
        _group('', [
          _item(Icons.logout_rounded, 'تسجيل الخروج', _logout, danger: true),
        ]),
        const SizedBox(height: 12),
        Center(child: Text('${Cfg.appName} v${Cfg.version}', style: E.t(12, c: E.ink3))),
      ]),
    );
  }

  Widget _group(String title, List<Widget> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(8, 18, 8, 8), child: Text(title, style: E.t(13, c: E.ink3))) else const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(color: E.card, borderRadius: BorderRadius.circular(12)),
          child: Column(children: items),
        ),
      ]);

  Widget _item(IconData i, String t, VoidCallback onTap, {String trailing = '', bool danger = false}) => ListTile(
        minTileHeight: 56,
        leading: Icon(i, color: danger ? E.accent : E.ink3),
        title: Text(t, style: E.t(15.5, w: FontWeight.w600, c: danger ? E.accent : E.ink)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing.isNotEmpty)
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150),
                child: Text(trailing, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(13, c: E.ink3))),
          if (!danger) Icon(Icons.chevron_left_rounded, color: E.ink3),
        ]),
        onTap: onTap,
      );

  Widget _switch(IconData i, String t, String sub, bool v, ValueChanged<bool> onChanged) => SwitchListTile(
        secondary: Icon(i, color: E.ink3),
        title: Text(t, style: E.t(15.5, w: FontWeight.w600)),
        subtitle: Text(sub, style: E.t(12.5, c: E.ink3)),
        value: v, activeColor: E.accent, onChanged: onChanged,
      );
}

/// الحساب: البريد · كلمة المرور · حذف الحساب
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  Future<void> _password(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: E.card,
        title: Text('كلمة مرور جديدة', style: E.t(17, w: FontWeight.w700)),
        content: TextField(controller: c, obscureText: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: '6 أحرف على الأقل')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await sb.auth.updateUser(UserAttributes(password: c.text));
      if (context.mounted) toast(context, 'تم تغيير كلمة المرور');
    } catch (e) {
      if (context.mounted) toast(context, errText(e));
    }
  }

  Future<void> _delete(BuildContext context) async {
    if (!await confirm(context, 'حذف الحساب نهائياً؟',
        'ستُحذف فيديوهاتك وتعليقاتك ورسائلك ومتابعوك ولا يمكن استرجاعها.', ok: 'حذف نهائي', danger: true)) return;
    if (!context.mounted) return;
    try {
      await Api.deleteAccount();
      if (context.mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        Shell.tab.value = 0;
      }
    } catch (e) {
      if (context.mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الحساب')),
        body: ListView(children: [
          ListTile(leading: const Icon(Icons.alternate_email_rounded), title: const Text('البريد'),
              subtitle: Text(sb.auth.currentUser?.email ?? '', textDirection: TextDirection.ltr)),
          ListTile(leading: const Icon(Icons.password_rounded), title: const Text('تغيير كلمة المرور'), onTap: () => _password(context)),
          const Divider(),
          ListTile(leading: const Icon(Icons.delete_forever_outlined, color: E.accent),
              title: Text('حذف الحساب', style: E.t(15, w: FontWeight.w700, c: E.accent)),
              subtitle: const Text('يحذف كل بياناتك نهائياً'), onTap: () => _delete(context)),
        ]),
      );
}

/// الحسابات المحظورة
class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key});
  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  List<Profile>? _l;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await sb.from('blocks').select('profiles!blocks_blocked_fkey(*)').eq('blocker', myId!);
      _l = [for (final m in r) if (m['profiles'] is Map) Profile.of(Map<String, dynamic>.from(m['profiles'] as Map))];
    } catch (_) {
      _l = [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الحسابات المحظورة')),
        body: _l == null
            ? const Loading()
            : _l!.isEmpty
                ? const EmptyState(icon: Icons.shield_outlined, title: 'لا حسابات محظورة')
                : ListView(children: [
                    for (final p in _l!)
                      ListTile(
                        leading: Avatar(p.avatar, name: p.username),
                        title: Text(p.display),
                        subtitle: Text('@${p.username}'),
                        trailing: TextButton(
                          onPressed: () async {
                            await Api.unblock(p.id);
                            _load();
                          },
                          child: const Text('إلغاء الحظر'),
                        ),
                      ),
                  ]),
      );
}

/// إدارة منشوراتي: كل فيديوهاتي مع الأرقام
class ManagePostsPage extends StatelessWidget {
  const ManagePostsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إدارة المنشورات')),
        body: FutureBuilder<List<Video>>(
          future: Api.ofUser(myId!, limit: 100),
          builder: (_, s) {
            if (!s.hasData) return const Loading();
            final l = s.data!;
            if (l.isEmpty) return const EmptyState(icon: Icons.video_library_outlined, title: 'لا منشورات بعد');
            return SingleChildScrollView(child: VideoGrid(items: l, onOpen: (k) => VideoListPage.open(context, l, k)));
          },
        ),
      );
}

/// التحليلات: أرقام آخر 28 يوماً لفيديوهاتي
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  Future<Map<String, dynamic>> _load() async {
    final vids = await Api.ofUser(myId!, limit: 100);
    final since = DateTime.now().subtract(const Duration(days: 28));
    final ids = vids.map((v) => v.id).toList();
    var views = 0, uniq = 0, completes = 0, watch = 0, shares = 0;
    if (ids.isNotEmpty) {
      final rows = await sb.from('video_daily').select().inFilter('video_id', ids)
          .gte('day', '${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}');
      for (final r in rows) {
        views += r.i('views'); uniq += r.i('uniq'); completes += r.i('completes'); watch += r.i('watch_ms'); shares += r.i('shares');
      }
    }
    vids.sort((a, b) => b.views.compareTo(a.views));
    return {'views': views, 'uniq': uniq, 'completes': completes, 'watch': watch, 'shares': shares, 'top': vids.take(10).toList(),
      'likes': vids.fold<int>(0, (a, v) => a + v.likes), 'comments': vids.fold<int>(0, (a, v) => a + v.comments)};
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('التحليلات')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _load(),
          builder: (_, s) {
            if (s.hasError) return EmptyState(icon: Icons.error_outline_rounded, title: 'تعذّر التحميل', sub: errText(s.error!));
            if (!s.hasData) return const Loading();
            final d = s.data!;
            final views = d['views'] as int;
            final top = d['top'] as List<Video>;
            final avg = views > 0 ? (d['watch'] as int) / views / 1000 : 0.0;
            final comp = views > 0 ? (d['completes'] as int) * 100 / views : 0.0;
            Widget tile(String n, String l) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: E.soft, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n, style: E.t(22, w: FontWeight.w800)),
                    Text(l, style: E.t(12.5, c: E.ink3)),
                  ]),
                );
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('آخر 28 يوماً', style: E.t(14, c: E.ink3)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.1,
                children: [
                  tile(fmtN(views), 'مشاهدات الفيديو'),
                  tile(fmtN(d['uniq'] as int), 'مشاهدون فريدون'),
                  tile('${avg.toStringAsFixed(1)} ث', 'متوسط المشاهدة'),
                  tile('${comp.toStringAsFixed(0)}%', 'شاهدوه كاملاً'),
                  tile(fmtN(d['likes'] as int), 'إعجابات (الكل)'),
                  tile(fmtN(d['shares'] as int), 'مشاركات'),
                ],
              ),
              const SizedBox(height: 22),
              Text('الأكثر مشاهدة', style: E.t(16, w: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final v in top)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 44, height: 58,
                      child: v.poster.isEmpty ? ColoredBox(color: E.soft) : CachedNetworkImage(imageUrl: v.poster, fit: BoxFit.cover))),
                  title: Text(v.caption.isEmpty ? '(بلا وصف)' : v.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('▶ ${fmtN(v.views)} · ♥ ${fmtN(v.likes)} · 💬 ${fmtN(v.comments)}', style: E.t(12.5, c: E.ink3)),
                  onTap: () => VideoListPage.open(context, top, top.indexOf(v)),
                ),
            ]);
          },
        ),
      );
}
