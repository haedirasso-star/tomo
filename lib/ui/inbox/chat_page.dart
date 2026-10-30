part of '../../main.dart';

/// محادثة خاصة: رسائل فورية · رد على رسالة · سحب للرد · نسخ · إلغاء الإرسال (48 ساعة) · «شوهدت» · إبلاغ
class ChatPage extends StatefulWidget {
  final String convId;
  final Profile other;
  const ChatPage({super.key, required this.convId, required this.other});

  static Future<void> open(BuildContext context, String convId, Profile other) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(convId: convId, other: other)));

  /// يفتح (أو ينشئ) محادثة مع حساب
  static Future<void> openWith(BuildContext context, Profile other) async {
    if (!await Me.ensure(context) || !context.mounted) return;
    try {
      final id = await Api.openConv(other.id);
      if (context.mounted) await open(context, id, other);
    } catch (e) {
      if (context.mounted) toast(context, errText(e));
    }
  }

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Msg> _msgs = [];
  final _c = TextEditingController();
  final _sc = ScrollController();
  bool _loading = true, _sending = false, _more = true;
  Msg? _reply;
  DateTime? _otherRead;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = sb.channel('chat-${widget.convId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert, schema: 'public', table: 'messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conv_id', value: widget.convId),
        callback: (p) {
          final m = Msg.of(Map<String, dynamic>.from(p.newRecord));
          if (!mounted || _msgs.any((x) => x.id == m.id)) return;
          setState(() => _msgs.insert(0, m));
          if (m.sender != myId) unawaited(Api.readConv(widget.convId));
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conv_id', value: widget.convId),
        callback: (p) {
          final m = Msg.of(Map<String, dynamic>.from(p.newRecord));
          final k = _msgs.indexWhere((x) => x.id == m.id);
          if (mounted && k >= 0) setState(() => _msgs[k] = m);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'conversations',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.convId),
        callback: (p) {
          final r = Map<String, dynamic>.from(p.newRecord);
          final iamA = r.s('a') == myId;
          final t = iamA ? r.d('read_b_at') : r.d('read_a_at');
          if (mounted && t != null) setState(() => _otherRead = t);
        },
      )
      ..subscribe();
    _sc.addListener(() {
      if (_sc.position.pixels > _sc.position.maxScrollExtent - 300) _loadMore();
    });
  }

  @override
  void dispose() {
    if (_ch != null) sb.removeChannel(_ch!);
    _c.dispose();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.messages(widget.convId);
      _msgs..clear()..addAll(r);
      _more = r.length >= 50;
      final convs = await sb.from('conversations').select().eq('id', widget.convId).maybeSingle();
      if (convs != null) {
        final iamA = convs.s('a') == myId;
        _otherRead = iamA ? convs.d('read_b_at') : convs.d('read_a_at');
      }
      unawaited(Api.readConv(widget.convId));
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _loadingMore = false;
  Future<void> _loadMore() async {
    if (!_more || _loadingMore || _msgs.isEmpty) return;
    _loadingMore = true;
    try {
      final r = await Api.messages(widget.convId, beforeId: _msgs.last.id);
      _more = r.length >= 50;
      if (mounted) setState(() => _msgs.addAll(r));
    } catch (_) {}
    _loadingMore = false;
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    final reply = _reply;
    try {
      final m = await Api.send(widget.convId, t, replyTo: reply?.id);
      _c.clear();
      setState(() {
        _reply = null;
        if (!_msgs.any((x) => x.id == m.id)) _msgs.insert(0, m);
      });
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _long(Msg m) async {
    if (m.deleted) return;
    HapticFeedback.mediumImpact();
    final mine = m.sender == myId;
    final canUnsend = mine && m.created != null && DateTime.now().difference(m.created!) < const Duration(hours: 48);
    final r = await sheetMenu<String>(context, [
      (Icons.reply_rounded, 'رد', 'reply', false),
      (Icons.copy_rounded, 'نسخ', 'copy', false),
      if (canUnsend) (Icons.undo_rounded, 'إلغاء الإرسال', 'unsend', true),
      if (!mine) (Icons.flag_outlined, 'إبلاغ', 'report', true),
    ]);
    if (!mounted || r == null) return;
    switch (r) {
      case 'reply':
        setState(() => _reply = m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) toast(context, 'نُسخ');
      case 'unsend':
        try { await Api.unsend(m.id); } catch (e) { if (mounted) toast(context, errText(e)); }
      case 'report':
        await reportFlow(context, 'message', '${m.id}');
    }
  }

  Future<void> _menu() async {
    final r = await sheetMenu<String>(context, [
      (Icons.person_outline_rounded, 'عرض الملف الشخصي', 'profile', false),
      (Icons.flag_outlined, 'إبلاغ عن الحساب', 'report', true),
      (Icons.block_rounded, 'حظر', 'block', true),
    ]);
    if (!mounted || r == null) return;
    if (r == 'profile') {
      UserPage.open(context, widget.other.id);
    } else if (r == 'report') {
      await reportFlow(context, 'user', widget.other.id);
    } else if (r == 'block') {
      if (!await confirm(context, 'حظر @${widget.other.username}؟', 'لن يستطيع مراسلتك أو رؤية فيديوهاتك.', ok: 'حظر', danger: true)) return;
      try {
        await Api.block(widget.other.id);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) toast(context, errText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.other;
    final byId = {for (final m in _msgs) m.id: m};
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => UserPage.open(context, o.id),
          child: Row(children: [
            Avatar(o.avatar, name: o.username, size: 36),
            const SizedBox(width: 10),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(15.5, w: FontWeight.w700)),
              Text('@${o.username}', style: E.t(12, c: E.ink3)),
            ])),
          ]),
        ),
        actions: [IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: _menu)],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(0.6), child: Divider(height: 0.6)),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Loading()
              : _msgs.isEmpty
                  ? EmptyState(icon: Icons.waving_hand_outlined, title: 'قل مرحباً لـ ${o.display}')
                  : ListView.builder(
                      controller: _sc,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        final mine = m.sender == myId;
                        final newestMine = mine && _msgs.indexWhere((x) => x.sender == myId) == i;
                        final seen = newestMine && _otherRead != null && m.created != null && !_otherRead!.isBefore(m.created!);
                        return _Bubble(
                          m: m, mine: mine, reply: m.replyTo > 0 ? byId[m.replyTo] : null,
                          showSeen: newestMine, seen: seen, otherName: o.display,
                          onLong: () => _long(m), onSwipe: () => setState(() => _reply = m),
                        );
                      },
                    ),
        ),
        if (_reply != null)
          Container(
            color: E.soft,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
            child: Row(children: [
              Container(width: 3, height: 34, color: E.accent),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_reply!.sender == myId ? 'الرد على نفسك' : 'الرد على ${o.display}', style: E.t(12.5, w: FontWeight.w700, c: E.accent)),
                Text(_reply!.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(13, c: E.ink2)),
              ])),
              IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => setState(() => _reply = null)),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c, minLines: 1, maxLines: 5, maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: 'رسالة…', counterText: '', isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: E.accent, shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _send,
                  child: SizedBox(width: 44, height: 44,
                      child: _sending
                          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 21)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatefulWidget {
  final Msg m;
  final Msg? reply;
  final bool mine, showSeen, seen;
  final String otherName;
  final VoidCallback onLong, onSwipe;
  const _Bubble({required this.m, required this.mine, this.reply, required this.showSeen, required this.seen,
      required this.otherName, required this.onLong, required this.onSwipe});
  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.m, mine = widget.mine;
    final bg = mine ? E.accent : E.soft;
    final fg = mine ? Colors.white : E.ink;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: m.deleted ? Colors.transparent : bg,
        border: m.deleted ? Border.all(color: E.line) : null,
        borderRadius: BorderRadius.circular(18),
      ),
      child: m.deleted
          ? Text('أُلغي إرسال الرسالة', style: E.t(13.5, c: E.ink3).copyWith(fontStyle: FontStyle.italic))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (widget.reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: mine ? Colors.white24 : Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text(widget.reply!.deleted ? 'رسالة محذوفة' : widget.reply!.body, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: E.t(12.5, c: mine ? Colors.white : E.ink2)),
                ),
              Text(m.body, style: E.t(15, c: fg, h: 1.35)),
            ]),
    );
    return GestureDetector(
      onLongPress: widget.onLong,
      onHorizontalDragUpdate: (d) => setState(() => _dx = (_dx + d.delta.dx).clamp(-70.0, 70.0)),
      onHorizontalDragEnd: (_) {
        if (_dx.abs() > 50) { HapticFeedback.selectionClick(); widget.onSwipe(); }
        setState(() => _dx = 0);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Transform.translate(offset: Offset(_dx, 0), child: bubble),
          if (widget.showSeen)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Text(widget.seen ? 'شوهدت' : 'أُرسلت', style: E.t(11, c: E.ink3)),
            ),
        ]),
      ),
    );
  }
}
