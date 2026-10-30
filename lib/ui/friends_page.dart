part of '../main.dart';

/// الأصدقاء: أصدقائي (متابعة متبادلة) + حسابات مقترحة + بحث
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  List<Profile> _friends = [], _suggested = [];
  Set<String> _followed = {};
  bool _loading = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    Me.rev.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Me.rev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.friends(), Api.suggested()]);
      _friends = r[0];
      _suggested = r[1];
      _followed = await Api.followingIds(_suggested.map((p) => p.id).toList());
      _err = '';
    } catch (e) {
      _err = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الأصدقاء'),
          actions: [IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())))],
        ),
        body: _loading
            ? const Loading()
            : RefreshIndicator(
                onRefresh: _load,
                color: E.accent,
                child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  if (_err.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_err, style: E.t(13, c: E.accent))),
                  if (Me.signedIn) ...[
                    _header('أصدقائي', _friends.isEmpty ? 'عندما تتابعان بعضكما تصبحان أصدقاء' : '${_friends.length}'),
                    if (_friends.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('لا أصدقاء بعد — تابع الحسابات المقترحة بالأسفل', style: E.t(14, c: E.ink3)))
                    else
                      for (final p in _friends) PersonTile(p, following: true, friend: true),
                  ],
                  _header('حسابات قد تعجبك', ''),
                  if (_suggested.isEmpty)
                    Padding(padding: const EdgeInsets.all(16), child: Text('لا اقتراحات الآن', style: E.t(14, c: E.ink3)))
                  else
                    for (final p in _suggested) PersonTile(p, following: _followed.contains(p.id)),
                ]),
              ),
      );

  Widget _header(String t, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Row(children: [
          Text(t, style: E.t(16, w: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(13, c: E.ink3))),
        ]),
      );
}

/// سطر حساب: الصورة · الاسم · @المستخدم · زر متابعة (أو مراسلة للأصدقاء)
class PersonTile extends StatefulWidget {
  final Profile p;
  final bool following, friend;
  const PersonTile(this.p, {super.key, this.following = false, this.friend = false});
  @override
  State<PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends State<PersonTile> {
  late bool _on = widget.following;
  bool _busy = false;

  Future<void> _toggle() async {
    if (!await Me.ensure(context) || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.follow(widget.p.id, !_on);
      _on = !_on;
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final mine = p.id == myId;
    return InkWell(
      onTap: () => UserPage.open(context, p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Avatar(p.avatar, name: p.username, size: 50),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(15, w: FontWeight.w700))),
              if (p.verified) const Verified(),
            ]),
            Text('@${p.username} · ${fmtN(p.followers)} متابِع', maxLines: 1, overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl, style: E.t(13, c: E.ink3)),
          ])),
          if (!mine) ...[
            const SizedBox(width: 8),
            if (widget.friend)
              Pill('مراسلة', height: 34, padding: const EdgeInsets.symmetric(horizontal: 14),
                  onTap: () => ChatPage.openWith(context, p))
            else
              Pill(_on ? 'تتابعه' : 'متابعة', primary: !_on, busy: _busy, height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16), onTap: _toggle),
          ],
        ]),
      ),
    );
  }
}

/// البحث عن حسابات
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _c = TextEditingController();
  Timer? _deb;
  List<Profile> _r = [];
  Set<String> _followed = {};
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _changed(String q) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    if (q.length < 2) { setState(() => _r = []); return; }
    setState(() => _busy = true);
    try {
      _r = await Api.search(q.replaceAll('@', ''));
      _followed = await Api.followingIds(_r.map((p) => p.id).toList());
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: TextField(
              controller: _c, autofocus: true, onChanged: _changed, textInputAction: TextInputAction.search,
              decoration: InputDecoration(hintText: 'ابحث عن حسابات', isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, color: E.ink3),
                  suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null),
            ),
          ),
        ),
        body: _r.isEmpty
            ? EmptyState(icon: Icons.person_search_outlined, title: _c.text.trim().length < 2 ? 'اكتب اسماً أو @اسم_مستخدم' : 'لا نتائج')
            : ListView(children: [for (final p in _r) PersonTile(p, following: _followed.contains(p.id))]),
      );
}
