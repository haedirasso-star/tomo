part of '../../main.dart';

/// صندوق الوارد: النشاط (إعجابات · تعليقات · متابعون جدد) + المحادثات الخاصة
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<Conv> _convs = [];
  int _unreadNotifs = 0;
  bool _loading = true;
  String _err = '';
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    Me.rev.addListener(_load);
    _load();
    _listen();
  }

  @override
  void dispose() {
    Me.rev.removeListener(_load);
    if (_ch != null) sb.removeChannel(_ch!);
    super.dispose();
  }

  /// أي تحديث على محادثاتي ⇐ إعادة تحميل القائمة
  void _listen() {
    if (!Me.signedIn) return;
    _ch = sb.channel('inbox-${myId!}')
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'conversations', callback: (_) => _load())
      ..subscribe();
  }

  Future<void> _load() async {
    if (!Me.signedIn) { if (mounted) setState(() { _convs = []; _loading = false; }); return; }
    try {
      final r = await Future.wait([Api.convs(), Api.unreadNotifs()]);
      _convs = r[0] as List<Conv>;
      _unreadNotifs = r[1] as int;
      Shell.inboxBadge.value = _unreadNotifs + _convs.fold<int>(0, (a, c) => a + c.unread);
      _err = '';
    } catch (e) {
      _err = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newChat() async {
    final friends = await Api.friends();
    if (!mounted) return;
    if (friends.isEmpty) { toast(context, 'المراسلة متاحة مع الأصدقاء (متابعة متبادلة)'); return; }
    final p = await showModalBottomSheet<Profile>(
      context: context, showDragHandle: true, backgroundColor: E.card, isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: ListView(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('رسالة جديدة', style: E.t(16, w: FontWeight.w800))),
          for (final f in friends)
            ListTile(
              leading: Avatar(f.avatar, name: f.username, size: 42),
              title: Text(f.display, style: E.t(15, w: FontWeight.w700)),
              subtitle: Text('@${f.username}', style: E.t(13, c: E.ink3)),
              onTap: () => Navigator.pop(ctx, f),
            ),
        ]),
      ),
    );
    if (p != null && mounted) {
      await ChatPage.openWith(context, p);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('صندوق الوارد'),
          actions: [IconButton(icon: const Icon(Icons.add_comment_outlined), onPressed: _newChat)],
        ),
        body: _loading
            ? const Loading()
            : RefreshIndicator(
                color: E.accent,
                onRefresh: _load,
                child: ListView(children: [
                  _row(Icons.notifications_rounded, E.accent, 'النشاط', 'الإعجابات والتعليقات والمتابعون الجدد', _unreadNotifs, () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityPage()));
                    _load();
                  }),
                  const Divider(height: 1, indent: 76),
                  if (_err.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(_err, style: E.t(13, c: E.accent))),
                  if (_convs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: EmptyState(icon: Icons.mark_chat_unread_outlined, title: 'لا رسائل بعد', sub: 'راسل أصدقاءك من زر ✚ بالأعلى'),
                    )
                  else
                    for (final c in _convs) _conv(c),
                ]),
              ),
      );

  Widget _row(IconData icon, Color color, String title, String sub, int badge, VoidCallback onTap) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(radius: 26, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 26)),
        title: Text(title, style: E.t(15.5, w: FontWeight.w700)),
        subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(13, c: E.ink3)),
        trailing: badge > 0 ? Badge(label: Text('$badge'), backgroundColor: E.accent) : Icon(Icons.chevron_left_rounded, color: E.ink3),
      );

  Widget _conv(Conv c) {
    final p = c.other;
    final mineLast = c.lastBy == myId;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () async {
        if (p == null) return;
        await ChatPage.open(context, c.id, p);
        _load();
      },
      leading: Avatar(p?.avatar ?? '', name: p?.username ?? '', size: 52),
      title: Text(p?.display ?? '...', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: E.t(15.5, w: c.unread > 0 ? FontWeight.w800 : FontWeight.w600)),
      subtitle: Text('${mineLast ? 'أنت: ' : ''}${c.lastBody.isEmpty ? 'ابدأ المحادثة' : c.lastBody} · ${ago(c.lastAt)}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: E.t(13, w: c.unread > 0 ? FontWeight.w700 : FontWeight.w400, c: c.unread > 0 ? E.ink : E.ink3)),
      trailing: c.unread > 0 ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: E.accent, shape: BoxShape.circle)) : null,
    );
  }
}

/// النشاط: من أعجب/علّق/تابع
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  List<Notif> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _items = await Api.notifs();
      unawaited(Api.readNotifs());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _text(Notif n) {
    switch (n.kind) {
      case 'like': return 'أعجبه الفيديو الخاص بك';
      case 'comment': return 'علّق: ${n.body}';
      case 'follow': return 'بدأ بمتابعتك';
      case 'mention': return 'أشار إليك: ${n.body}';
    }
    return n.body;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('النشاط')),
        body: _loading
            ? const Loading()
            : _items.isEmpty
                ? const EmptyState(icon: Icons.notifications_none_rounded, title: 'لا نشاط بعد', sub: 'عندما يتفاعل أحد مع فيديوهاتك سيظهر هنا')
                : RefreshIndicator(
                    color: E.accent,
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        final a = n.actor;
                        return ListTile(
                          tileColor: n.read ? null : E.accent.withOpacity(0.05),
                          onTap: () async {
                            if (n.videoId.isNotEmpty) {
                              final v = await Api.video(n.videoId);
                              if (v != null && context.mounted) VideoListPage.open(context, [v], 0);
                            } else if (a != null) {
                              UserPage.open(context, a.id);
                            }
                          },
                          leading: GestureDetector(onTap: a == null ? null : () => UserPage.open(context, a.id),
                              child: Avatar(a?.avatar ?? '', name: a?.username ?? '', size: 46)),
                          title: Text(a?.display ?? Cfg.appName, style: E.t(14.5, w: FontWeight.w700)),
                          subtitle: Text('${_text(n)} · ${ago(n.created)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: E.t(13, c: E.ink2)),
                          trailing: Icon(
                            n.kind == 'like' ? Icons.favorite_rounded : n.kind == 'comment' ? Icons.chat_bubble_rounded : Icons.person_add_alt_1_rounded,
                            color: n.kind == 'like' ? E.accent : E.ink3, size: 20),
                        );
                      },
                    ),
                  ),
      );
}
