part of '../../main.dart';

/// التعليقات: ورقة سفلية بثلثي الشاشة
class CommentsSheet extends StatefulWidget {
  final Video video;
  const CommentsSheet({super.key, required this.video});

  static Future<void> show(BuildContext context, Video v) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        builder: (_) => CommentsSheet(video: v),
      );

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  List<Comment> _items = [];
  bool _loading = true, _sending = false;
  String _err = '';
  final _c = TextEditingController();

  Video get v => widget.video;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _items = await Api.comments(v.id);
      _err = '';
    } catch (e) {
      _err = errText(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    if (!await Me.ensure(context) || !mounted) return;
    setState(() => _sending = true);
    try {
      final c = await Api.addComment(v.id, t);
      _c.clear();
      setState(() { _items.insert(0, c); v.comments++; });
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _long(Comment c) async {
    final canDelete = c.userId == myId || v.userId == myId;
    final r = await sheetMenu<String>(context, [
      (Icons.copy_rounded, 'نسخ', 'copy', false),
      if (canDelete) (Icons.delete_outline_rounded, 'حذف', 'delete', true),
      if (c.userId != myId) (Icons.flag_outlined, 'إبلاغ', 'report', true),
    ]);
    if (!mounted || r == null) return;
    if (r == 'copy') {
      await Clipboard.setData(ClipboardData(text: c.body));
    } else if (r == 'delete') {
      try {
        await Api.deleteComment(c.id);
        setState(() { _items.removeWhere((x) => x.id == c.id); v.comments = math.max(0, v.comments - 1); });
      } catch (e) {
        if (mounted) toast(context, errText(e));
      }
    } else if (r == 'report') {
      await reportFlow(context, 'comment', '${c.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.68;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: h,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Stack(alignment: Alignment.center, children: [
              Text('${fmtN(v.comments)} تعليق', style: E.t(14, w: FontWeight.w700)),
              PositionedDirectional(end: 0, child: IconButton(icon: const Icon(Icons.close_rounded, size: 22), onPressed: () => Navigator.pop(context))),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Loading()
                : !v.allowComments
                    ? const EmptyState(icon: Icons.comments_disabled_outlined, title: 'التعليقات مغلقة على هذا الفيديو')
                    : _items.isEmpty
                        ? EmptyState(icon: Icons.chat_bubble_outline_rounded, title: _err.isNotEmpty ? 'تعذّر التحميل' : 'كن أول من يعلّق', sub: _err)
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final c = _items[i];
                              return InkWell(
                                onLongPress: () => _long(c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    GestureDetector(onTap: () => UserPage.open(context, c.userId), child: Avatar(c.avatar, name: c.username, size: 36)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Text(c.username, style: E.t(13, w: FontWeight.w700, c: E.ink2)),
                                        if (c.userId == v.userId) ...[
                                          const SizedBox(width: 6),
                                          Text('· صاحب الفيديو', style: E.t(12, w: FontWeight.w700, c: E.accent)),
                                        ],
                                      ]),
                                      const SizedBox(height: 2),
                                      Text(c.body, style: E.t(14.5, h: 1.35)),
                                      const SizedBox(height: 4),
                                      Text(ago(c.created), style: E.t(12, c: E.ink3)),
                                    ])),
                                  ]),
                                ),
                              );
                            },
                          ),
          ),
          if (v.allowComments)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: E.line))),
                child: Row(children: [
                  Avatar(Me.profile?.avatar ?? '', name: Me.profile?.username ?? '', size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _c,
                      minLines: 1, maxLines: 4, maxLength: 500,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'أضف تعليقاً…', counterText: '', isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _sending
                      ? const SizedBox(width: 36, height: 36, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.arrow_upward_rounded, color: E.accent), onPressed: _send),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
