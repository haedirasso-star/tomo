part of '../../main.dart';

/// فيديو واحد بملء الشاشة + الأزرار الجانبية (الصورة · إعجاب · تعليق · حفظ · مشاركة) + الاسم والوصف
///  ضغطة = إيقاف/تشغيل · ضغطتان = ❤ حيث الإصبع · ضغط مطوّل = قائمة (ليس مهتماً · إبلاغ · حذف لصاحبه)
class VideoView extends StatefulWidget {
  final Video video;
  final VideoPlayerController? ctl;
  final bool broken, paused;
  final VoidCallback onTap, onRetry;
  final VideoPagerState pager;
  const VideoView({super.key, required this.video, required this.ctl, required this.broken, required this.paused,
      required this.onTap, required this.onRetry, required this.pager});
  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  Video get v => widget.video;
  final List<(Offset, int)> _hearts = [];
  int _heartN = 0;
  bool _expanded = false, _following = false, _followKnown = false;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    if (!Me.signedIn || v.userId == myId) { _followKnown = true; return; }
    try {
      _following = await Api.isFollowing(v.userId);
    } catch (_) {}
    if (mounted) setState(() => _followKnown = true);
  }

  Future<void> _like({bool force = false}) async {
    if (!await Me.ensure(context) || !mounted) return;
    if (force && v.liked) return;
    final on = !v.liked;
    setState(() { v.liked = on; v.likes += on ? 1 : -1; });
    HapticFeedback.lightImpact();
    try {
      await Api.like(v, on);
    } catch (e) {
      if (mounted) setState(() { v.liked = !on; v.likes += on ? -1 : 1; });
    }
  }

  void _doubleTap(TapDownDetails d) {
    final id = _heartN++;
    setState(() => _hearts.add((d.localPosition, id)));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _hearts.removeWhere((h) => h.$2 == id));
    });
    _like(force: true);
  }

  Future<void> _save() async {
    if (!await Me.ensure(context) || !mounted) return;
    final on = !v.saved;
    setState(() { v.saved = on; v.saves += on ? 1 : -1; });
    HapticFeedback.lightImpact();
    try {
      await Api.save(v, on);
      if (mounted && on) toast(context, 'حُفظ في المفضلة');
    } catch (_) {
      if (mounted) setState(() { v.saved = !on; v.saves += on ? -1 : 1; });
    }
  }

  Future<void> _follow() async {
    if (!await Me.ensure(context) || !mounted) return;
    setState(() => _following = true);
    HapticFeedback.mediumImpact();
    try {
      await Api.follow(v.userId, true);
    } catch (e) {
      if (mounted) { setState(() => _following = false); toast(context, errText(e)); }
    }
  }

  Future<void> _comments() async {
    await widget.pager.pauseDuring(() => CommentsSheet.show(context, v));
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    Trk.ev('s', v.id, cid: v.cid);
    setState(() => v.shares++);
    final link = '${Cfg.siteUrl}/v/${v.id}';
    await widget.pager.pauseDuring(() => Share.share('${v.caption.isNotEmpty ? '${v.caption}\n' : ''}@${v.username} على ${Cfg.appName}\n$link'));
  }

  Future<void> _openAuthor() async {
    await widget.pager.pauseDuring(() => UserPage.open(context, v.userId));
  }

  Future<void> _menu() async {
    HapticFeedback.mediumImpact();
    final mine = v.userId == myId;
    final r = await widget.pager.pauseDuring(() => sheetMenu<String>(context, [
          if (mine) (Icons.local_fire_department_outlined, 'روّج هذا الفيديو', 'promote', false),
          if (mine) (Icons.lock_outline_rounded, 'من يمكنه المشاهدة', 'privacy', false),
          if (mine) (Icons.delete_outline_rounded, 'حذف الفيديو', 'delete', true),
          if (!mine) (Icons.heart_broken_outlined, 'لست مهتماً', 'skip', false),
          if (!mine) (Icons.flag_outlined, 'إبلاغ', 'report', true),
          if (!mine) (Icons.block_rounded, 'حظر @${v.username}', 'block', true),
        ]));
    if (!mounted || r == null) return;
    switch (r) {
      case 'promote':
        await widget.pager.pauseDuring(() => openPromote(context, v));
      case 'privacy':
        final p = await sheetMenu<String>(context, [
          (Icons.public_rounded, 'الجميع', 'public', false),
          (Icons.people_outline_rounded, 'الأصدقاء فقط', 'friends', false),
          (Icons.lock_outline_rounded, 'أنا فقط', 'private', false),
        ]);
        if (p != null) {
          try { await Api.setPrivacy(v, p); if (mounted) toast(context, 'تم'); } catch (e) { if (mounted) toast(context, errText(e)); }
        }
      case 'delete':
        if (!await confirm(context, 'حذف الفيديو؟', 'سيُحذف نهائياً مع تعليقاته وإعجاباته.', ok: 'حذف', danger: true)) return;
        try {
          await Api.deleteVideo(v);
          widget.pager.removeAt(v.id);
          Me.refresh();
        } catch (e) {
          if (mounted) toast(context, errText(e));
        }
      case 'skip':
        widget.pager.removeAt(v.id);
      case 'report':
        await reportFlow(context, 'video', v.id);
      case 'block':
        if (!await confirm(context, 'حظر @${v.username}؟', 'لن ترى فيديوهاته ولن يستطيع مراسلتك أو التعليق على فيديوهاتك.', ok: 'حظر', danger: true)) return;
        try { await Api.block(v.userId); widget.pager.removeAt(v.id); } catch (e) { if (mounted) toast(context, errText(e)); }
    }
  }

  Future<void> _cta() async {
    final u = Uri.tryParse(v.ctaLink);
    if (u == null) return;
    Trk.ev('c', v.id, cid: v.cid);
    await widget.pager.pauseDuring(() async => launchUrl(u, mode: LaunchMode.externalApplication));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctl;
    final ready = c != null && c.value.isInitialized;
    final bottomPad = MediaQuery.of(context).padding.bottom > 0 ? 8.0 : 12.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: _doubleTap,
      onDoubleTap: () {},
      onLongPress: _menu,
      child: Stack(fit: StackFit.expand, children: [
        // ── الصورة: الغلاف فوراً حتى أول إطار، والفيديو بلا قصّ مزعج ──
        if (v.poster.isNotEmpty && !ready)
          CachedNetworkImage(imageUrl: v.poster, fit: v.landscape ? BoxFit.contain : BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
        if (ready) _video(c),
        if (!ready && !widget.broken) const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))),
        if (widget.broken)
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 42),
            TextButton(onPressed: widget.onRetry, child: Text('إعادة المحاولة', style: E.t(14, w: FontWeight.w700, c: Colors.white))),
          ])),
        // تظليل خفيف أسفل الشاشة لقراءة النص
        const Positioned(left: 0, right: 0, bottom: 0, height: 260,
            child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0x99000000), Color(0x00000000)]))))),
        if (widget.paused)
          const Center(child: IgnorePointer(child: Icon(Icons.play_arrow_rounded, size: 84, color: Colors.white70))),
        for (final h in _hearts)
          Positioned(left: h.$1.dx - 50, top: h.$1.dy - 60, child: const IgnorePointer(child: _Heart())),
        // ── العمود الجانبي ──
        PositionedDirectional(
          end: 8, bottom: bottomPad + 18,
          child: Column(children: [
            _avatar(),
            const SizedBox(height: 18),
            _side(Icons.favorite_rounded, fmtN(v.likes), _like, color: v.liked ? E.accent : Colors.white),
            _side(Icons.chat_bubble_rounded, fmtN(v.comments), _comments),
            _side(Icons.bookmark_rounded, fmtN(v.saves), _save, color: v.saved ? const Color(0xFFFACE15) : Colors.white),
            _side(Icons.reply_rounded, v.shares > 0 ? fmtN(v.shares) : 'مشاركة', _share, mirror: true),
          ]),
        ),
        // ── الاسم والوصف ──
        PositionedDirectional(
          start: 12, end: 84, bottom: bottomPad + 6,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: _openAuthor,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(v.authorName.isNotEmpty ? v.authorName : v.username, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: E.t(16, w: FontWeight.w800, c: Colors.white))),
                if (v.authorVerified) const Verified(),
                if (v.sponsored) ...[
                  const SizedBox(width: 6),
                  Text('· إعلان', style: E.t(13, w: FontWeight.w600, c: Colors.white70)),
                ],
              ]),
            ),
            if (v.caption.isNotEmpty) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(v.caption, maxLines: _expanded ? 12 : 2, overflow: TextOverflow.ellipsis,
                    style: E.t(14.5, c: Colors.white, h: 1.35)),
              ),
            ],
            if (v.userId == myId && !v.sponsored) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.play_arrow_outlined, color: Colors.white, size: 18),
                Text('${fmtN(v.views)} مشاهدة', style: E.t(13, w: FontWeight.w700, c: Colors.white)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => widget.pager.pauseDuring(() => openPromote(context, v)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white38)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('روّج', style: E.t(13, w: FontWeight.w800, c: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ],
            if (v.sponsored && v.ctaLink.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _cta,
                child: Container(
                  height: 40, alignment: Alignment.center,
                  decoration: BoxDecoration(color: E.accent, borderRadius: BorderRadius.circular(6)),
                  child: Text(v.ctaLabel.isNotEmpty ? v.ctaLabel : 'اعرف المزيد', style: E.t(14.5, w: FontWeight.w800, c: Colors.white)),
                ),
              ),
            ],
          ]),
        ),
        // ── شريط التقدّم ──
        if (ready)
          Positioned(left: 0, right: 0, bottom: 0, height: 2.5,
              child: VideoProgressIndicator(c, allowScrubbing: true, padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white24, backgroundColor: Colors.white12))),
      ]),
    );
  }

  /// عمودي ⇐ يملأ الشاشة (يقصّ الحواف القليلة فقط) · أفقي ⇐ يظهر كاملاً في المنتصف
  Widget _video(VideoPlayerController c) {
    final ar = c.value.aspectRatio;
    final screen = MediaQuery.of(context).size;
    final screenAr = screen.width / screen.height;
    final fill = ar < 1 && (ar - screenAr).abs() / screenAr < 0.22;
    final sz = c.value.size;
    return FittedBox(
      fit: fill ? BoxFit.cover : BoxFit.contain,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: sz.width > 0 ? sz.width : 720, height: sz.height > 0 ? sz.height : 1280, child: VideoPlayer(c)),
    );
  }

  Widget _avatar() => SizedBox(
        width: 52, height: 62,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          GestureDetector(onTap: _openAuthor, child: Avatar(v.authorAvatar, name: v.username, size: 48, ring: true)),
          if (_followKnown && !_following && v.userId != myId)
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: _follow,
                child: Container(
                  width: 22, height: 22,
                  decoration: const BoxDecoration(color: E.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
        ]),
      );

  Widget _side(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white, bool mirror = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 56,
            child: Column(children: [
              Transform.flip(flipX: mirror, child: Icon(icon, size: 36, color: color,
                  shadows: const [Shadow(blurRadius: 6, color: Colors.black38)])),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, style: E.t(12.5, w: FontWeight.w700, c: Colors.white).copyWith(
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)])),
            ]),
          ),
        ),
      );
}

class _Heart extends StatelessWidget {
  const _Heart();
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 750),
        builder: (_, t, __) => Opacity(
          opacity: t < 0.7 ? 1 : (1 - (t - 0.7) / 0.3),
          child: Transform.translate(
            offset: Offset(0, -40 * t),
            child: Transform.scale(scale: 0.6 + 0.6 * Curves.elasticOut.transform(math.min(1, t * 1.6)),
                child: const Icon(Icons.favorite_rounded, size: 100, color: E.accent)),
          ),
        ),
      );
}
