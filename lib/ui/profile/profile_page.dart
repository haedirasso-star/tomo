part of '../../main.dart';

/// ملفي الشخصي (تبويب الشريط السفلي)
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Me.rev,
        builder: (_, __, ___) {
          final id = myId;
          if (id == null) {
            return Scaffold(
              body: EmptyState(
                icon: Icons.person_outline_rounded, title: 'سجّل الدخول لترى ملفك الشخصي',
                action: Pill('دخول أو إنشاء حساب', primary: true, onTap: () => Me.ensure(context)),
              ),
            );
          }
          return ProfileView(key: ValueKey('me_$id'), uid: id, initial: Me.profile, isTab: true);
        },
      );
}

/// ملف حساب آخر
class UserPage extends StatelessWidget {
  final String uid;
  const UserPage({super.key, required this.uid});

  static Future<void> open(BuildContext context, String uid) {
    if (uid == myId) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      Shell.tab.value = 4;
      return Future.value();
    }
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserPage(uid: uid)));
  }

  @override
  Widget build(BuildContext context) => ProfileView(uid: uid);
}

class ProfileView extends StatefulWidget {
  final String uid;
  final Profile? initial;
  final bool isTab;
  const ProfileView({super.key, required this.uid, this.initial, this.isTab = false});
  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> with SingleTickerProviderStateMixin {
  Profile? _p;
  bool _loading = true, _following = false, _followsMe = false, _busy = false;
  String _err = '';
  final Map<int, List<Video>?> _tabs = {};
  late final TabController _tc;

  bool get _mine => widget.uid == myId;

  @override
  void initState() {
    super.initState();
    _p = widget.initial;
    _tc = TabController(length: _mine ? 4 : 1, vsync: this)..addListener(() {
        if (!_tc.indexIsChanging) _loadTab(_tc.index);
      });
    _load();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Api.profile(widget.uid);
      if (p == null) throw Exception('الحساب غير موجود');
      _p = p;
      if (_mine) Me.profile = p;
      if (!_mine && Me.signedIn) {
        final r = await Future.wait<Object?>([
          Api.isFollowing(widget.uid),
          sb.from('follows').select('follower').eq('follower', widget.uid).eq('followee', myId!).maybeSingle(),
        ]);
        _following = r[0] as bool;
        _followsMe = r[1] != null;
      }
      _err = '';
    } catch (e) {
      _err = errText(e);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _tabs.clear();
    _loadTab(_tc.index);
  }

  Future<void> _loadTab(int i) async {
    if (_tabs[i] != null) return;
    try {
      List<Video> l;
      switch (i) {
        case 0:
          l = (await Api.ofUser(widget.uid)).where((v) => !_mine || v.privacy != 'private').toList();
        case 1:
          l = (await Api.ofUser(widget.uid)).where((v) => v.privacy == 'private').toList();
        case 2:
          l = await Api.saved();
        default:
          l = await Api.liked();
      }
      if (mounted) setState(() => _tabs[i] = l);
    } catch (e) {
      if (mounted) setState(() => _tabs[i] = const []);
    }
  }

  Future<void> _toggleFollow() async {
    if (!await Me.ensure(context) || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.follow(widget.uid, !_following);
      _following = !_following;
      final p = await Api.profile(widget.uid);
      if (p != null) _p = p;
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  void _shareProfile() {
    final p = _p;
    if (p == null) return;
    Share.share('تابع ${p.display} (@${p.username}) على ${Cfg.appName}\n${Cfg.siteUrl}/@${p.username}');
  }

  Future<void> _otherMenu() async {
    final p = _p;
    if (p == null) return;
    final r = await sheetMenu<String>(context, [
      (Icons.ios_share_rounded, 'مشاركة الملف الشخصي', 'share', false),
      (Icons.flag_outlined, 'إبلاغ', 'report', true),
      (Icons.block_rounded, 'حظر', 'block', true),
    ]);
    if (!mounted || r == null) return;
    if (r == 'share') _shareProfile();
    if (r == 'report') await reportFlow(context, 'user', p.id);
    if (r == 'block') {
      if (!await confirm(context, 'حظر @${p.username}؟', 'لن ترى فيديوهاته ولن يستطيع مراسلتك أو رؤية محتواك.', ok: 'حظر', danger: true)) return;
      try {
        await Api.block(p.id);
        if (mounted) { toast(context, 'تم الحظر'); Navigator.of(context).maybePop(); }
      } catch (e) {
        if (mounted) toast(context, errText(e));
      }
    }
  }

  void _openList(bool followers) {
    final p = _p;
    if (p == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserListPage(uid: p.id, followers: followers, title: p.display)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      endDrawer: _mine ? const _MenuDrawer() : null,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isTab,
        leading: widget.isTab
            ? IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'تعديل الملف الشخصي', onPressed: _edit)
            : null,
        title: p == null
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: E.soft, borderRadius: BorderRadius.circular(20)),
                child: Text('@${p.username}', textDirection: TextDirection.ltr, style: E.t(14, w: FontWeight.w600)),
              ),
        actions: [
          if (_mine) ...[
            IconButton(icon: const Icon(Icons.person_add_alt_outlined), tooltip: 'إضافة أصدقاء',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage()))),
            Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => Scaffold.of(ctx).openEndDrawer())),
          ] else
            IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: _otherMenu),
        ],
      ),
      body: _loading && p == null
          ? const Loading()
          : p == null
              ? EmptyState(icon: Icons.error_outline_rounded, title: 'تعذّر التحميل', sub: _err,
                  action: TextButton(onPressed: _load, child: const Text('إعادة المحاولة')))
              : RefreshIndicator(
                  color: E.accent,
                  onRefresh: _load,
                  child: NestedScrollView(
                    headerSliverBuilder: (_, __) => [
                      SliverToBoxAdapter(child: _header(p)),
                      SliverPersistentHeader(pinned: true, delegate: _TabsHeader(_tabBar())),
                    ],
                    body: TabBarView(
                      controller: _tc,
                      children: [for (int i = 0; i < _tc.length; i++) _grid(i, p)],
                    ),
                  ),
                ),
    );
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const EditProfilePage()));
    if (changed == true) _load();
  }

  Widget _header(Profile p) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(p.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(26, w: FontWeight.w800))),
                  if (p.verified) const Verified(size: 20),
                ]),
                Text('@${p.username}', textDirection: TextDirection.ltr, style: E.t(14.5, c: E.ink3)),
                const SizedBox(height: 14),
                Row(children: [
                  _stat(fmtN(p.following), 'أتابعه', () => _openList(false)),
                  const SizedBox(width: 22),
                  _stat(fmtN(p.followers), 'متابعين', () => _openList(true)),
                  const SizedBox(width: 22),
                  _stat(fmtN(p.likes), 'تسجيلات الإعجاب', null),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            Stack(clipBehavior: Clip.none, children: [
              GestureDetector(onTap: _mine ? _edit : null, child: Avatar(p.avatar, name: p.username, size: 96)),
              if (_mine)
                PositionedDirectional(
                  bottom: 0, end: 0,
                  child: GestureDetector(
                    onTap: _edit,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: E.online, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
            ]),
          ]),
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(p.bio, style: E.t(14.5, h: 1.4)),
          ],
          if (p.link.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                final u = Uri.tryParse(p.link.startsWith('http') ? p.link : 'https://${p.link}');
                if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.link_rounded, size: 17, color: E.ink),
                const SizedBox(width: 4),
                Flexible(child: Text(p.link, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
                    style: E.t(14, w: FontWeight.w700))),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          if (_mine)
            Row(children: [
              Expanded(child: Pill('تعديل الملف الشخصي', height: 40, onTap: _edit)),
              const SizedBox(width: 8),
              Expanded(child: Pill('مشاركة الملف الشخصي', height: 40, onTap: _shareProfile)),
            ])
          else
            Row(children: [
              Expanded(child: Pill(_following ? 'تتابعه' : (_followsMe ? 'رد المتابعة' : 'متابعة'),
                  primary: !_following, busy: _busy, height: 42, onTap: _toggleFollow)),
              if (_following && _followsMe) ...[
                const SizedBox(width: 8),
                Expanded(child: Pill('مراسلة', height: 42, onTap: () => ChatPage.openWith(context, p))),
              ],
            ]),
          const SizedBox(height: 10),
        ]),
      );

  Widget _stat(String n, String label, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, style: E.t(18, w: FontWeight.w800)),
          Text(label, style: E.t(12.5, c: E.ink3)),
        ]),
      );

  TabBar _tabBar() => TabBar(
        controller: _tc,
        indicatorColor: E.ink,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: E.ink,
        unselectedLabelColor: E.ink3,
        dividerColor: E.line,
        tabs: [
          const Tab(icon: Icon(Icons.grid_view_rounded)),
          if (_mine) ...[
            const Tab(icon: Icon(Icons.lock_outline_rounded)),
            const Tab(icon: Icon(Icons.bookmark_border_rounded)),
            const Tab(icon: Icon(Icons.favorite_border_rounded)),
          ],
        ],
      );

  Widget _grid(int i, Profile p) {
    final l = _tabs[i];
    if (l == null) return const Loading();
    if (!_mine && p.private && !(_following && _followsMe)) {
      return const EmptyState(icon: Icons.lock_outline_rounded, title: 'هذا الحساب خاص', sub: 'تابعه وتابعك لترى فيديوهاته');
    }
    if (l.isEmpty) {
      const titles = ['لا فيديوهات بعد', 'لا فيديوهات خاصة', 'لا محفوظات بعد', 'لم يعجبك شيء بعد'];
      return EmptyState(
        icon: const [Icons.video_library_outlined, Icons.lock_outline_rounded, Icons.bookmark_border_rounded, Icons.favorite_border_rounded][i],
        title: titles[i],
        sub: i == 0 && _mine ? 'انشر أول فيديو من زر ✚ بالأسفل' : '',
      );
    }
    return SingleChildScrollView(
      child: VideoGrid(items: l, onOpen: (k) async {
        await VideoListPage.open(context, l, k);
        if (mounted) setState(() => _tabs.clear());
        _loadTab(_tc.index);
      }),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabBar bar;
  _TabsHeader(this.bar);
  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(color: E.bg, child: bar);
  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.bar != bar;
}

/// القائمة الجانبية (☰): الأدوات والإعدادات
class _MenuDrawer extends StatelessWidget {
  const _MenuDrawer();

  @override
  Widget build(BuildContext context) {
    void go(Widget page) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 6), child: Text(t, style: E.t(13, c: E.ink3)));
    Widget item(IconData i, String t, VoidCallback onTap) => ListTile(
          leading: Icon(i, color: E.ink, size: 26),
          title: Text(t, style: E.t(16, w: FontWeight.w600)),
          trailing: Icon(Icons.chevron_left_rounded, color: E.ink3),
          onTap: onTap,
        );

    return Drawer(
      backgroundColor: E.card,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListView(children: [
          head('الأصول'),
          item(Icons.account_balance_wallet_outlined, 'رصيد', () => go(const ComingSoonPage(title: 'رصيد', sub: 'العملات والهدايا وأرباح صنّاع المحتوى — قريباً'))),
          const Divider(indent: 20, endIndent: 20),
          head('الأدوات الشخصية'),
          item(Icons.history_rounded, 'مركز الأنشطة', () => go(const ActivityPage())),
          item(Icons.download_for_offline_outlined, 'فيديوهات محفوظة', () => go(const SavedVideosPage())),
          item(Icons.qr_code_2_rounded, 'مشاركة ملفي', () {
            Navigator.pop(context);
            final p = Me.profile;
            if (p != null) Share.share('تابعني على ${Cfg.appName}: ${Cfg.siteUrl}/@${p.username}');
          }),
          const Divider(indent: 20, endIndent: 20),
          head('أدوات الإبداع والأعمال'),
          item(Icons.insights_rounded, 'التحليلات', () => go(const AnalyticsPage())),
          item(Icons.local_fire_department_outlined, 'الترويج وترويجاتي', () => go(const MyPromosPage())),
          if (Me.profile?.staff == true) item(Icons.admin_panel_settings_outlined, 'لوحة الإدارة', () => go(const AdminPage())),
          const Divider(indent: 20, endIndent: 20),
          item(Icons.settings_outlined, 'الإعدادات والخصوصية', () => go(const SettingsPage())),
        ]),
      ),
    );
  }
}

class ComingSoonPage extends StatelessWidget {
  final String title, sub;
  const ComingSoonPage({super.key, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(icon: Icons.rocket_launch_outlined, title: 'قريباً', sub: sub),
      );
}

class SavedVideosPage extends StatelessWidget {
  const SavedVideosPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحفوظات')),
        body: FutureBuilder<List<Video>>(
          future: Api.saved(),
          builder: (_, s) {
            if (!s.hasData) return const Loading();
            final l = s.data!;
            if (l.isEmpty) return const EmptyState(icon: Icons.bookmark_border_rounded, title: 'لا محفوظات بعد');
            return SingleChildScrollView(child: VideoGrid(items: l, onOpen: (k) => VideoListPage.open(context, l, k)));
          },
        ),
      );
}
