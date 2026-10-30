part of '../main.dart';

/// النشر: اختيار فيديو (المعرض أو الكاميرا) ⇐ معاينة ⇐ الوصف والوسوم ⇐ من يشاهده ⇐ نشر
class PostPage extends StatefulWidget {
  const PostPage({super.key});
  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  io.File? _file, _poster;
  VideoPlayerController? _ctl;
  final _caption = TextEditingController();
  String _privacy = 'public', _err = '';
  bool _comments = true, _busy = false;
  double _prog = 0;

  @override
  void dispose() {
    _ctl?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(seconds: Cfg.maxVideoSeconds));
    if (x == null) return;
    final f = io.File(x.path);
    final size = await f.length();
    if (size > Cfg.maxVideoBytes) {
      setState(() => _err = 'الفيديو أكبر من ${Cfg.maxVideoBytes ~/ (1024 * 1024)}MB — اختر فيديو أقصر');
      return;
    }
    final c = VideoPlayerController.file(f);
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      setState(() => _err = 'تعذّر فتح هذا الفيديو — جرّب فيديو آخر');
      return;
    }
    if (c.value.duration.inSeconds > Cfg.maxVideoSeconds + 1) {
      await c.dispose();
      setState(() => _err = 'أقصى طول ${Cfg.maxVideoSeconds ~/ 60} دقائق');
      return;
    }
    await _ctl?.dispose();
    c.setLooping(true);
    c.setVolume(0);
    c.play();
    setState(() { _file = f; _ctl = c; _err = ''; _poster = null; });
    unawaited(_makePoster(f));
  }

  Future<void> _makePoster(io.File f) async {
    try {
      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/tomo_poster_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ok = await FcNativeVideoThumbnail().getVideoThumbnail(
        srcFile: f.path, destFile: out, width: 540, height: 960, format: 'jpeg', quality: 82);
      if (ok && mounted && _file == f) setState(() => _poster = io.File(out));
    } catch (e) {
      debugPrint('[poster] $e');
    }
  }

  Future<void> _publish() async {
    final f = _file, c = _ctl;
    if (f == null || c == null) return;
    setState(() { _busy = true; _err = ''; _prog = 0; });
    c.pause();
    try {
      final processing = await Api.publish(
        file: f, poster: _poster, caption: _caption.text.trim(), privacy: _privacy, allowComments: _comments,
        duration: c.value.duration.inSeconds, width: c.value.size.width.round(), height: c.value.size.height.round(),
        onProgress: (p) { if (mounted) setState(() => _prog = p); },
      );
      if (!mounted) return;
      toast(context, processing ? 'رُفع ✓ — نجهّزه بأفضل جودة ويظهر خلال دقيقة' : 'نُشر الفيديو ✓');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e); });
      c.play();
    }
  }

  void _addTag() {
    final t = _caption.text;
    _caption.text = '${t.isEmpty || t.endsWith(' ') ? t : '$t '}#';
    _caption.selection = TextSelection.collapsed(offset: _caption.text.length);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _busy ? null : () => Navigator.pop(context)),
          title: const Text('نشر'),
        ),
        body: _file == null ? _chooser() : _form(),
      );

  Widget _chooser() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.video_call_outlined, size: 72, color: E.ink3),
            const SizedBox(height: 14),
            Text('شارك فيديو', style: E.t(20, w: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('حتى ${Cfg.maxVideoSeconds ~/ 60} دقائق · عمودي أفضل', style: E.t(14, c: E.ink3)),
            const SizedBox(height: 26),
            SizedBox(width: double.infinity, child: Pill('اختر من المعرض', primary: true, icon: Icons.photo_library_outlined, height: 50,
                onTap: () => _pick(ImageSource.gallery))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: Pill('صوّر الآن', icon: Icons.videocam_outlined, height: 50,
                onTap: () => _pick(ImageSource.camera))),
            if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_err, textAlign: TextAlign.center, style: E.t(13, c: E.accent))),
            const SizedBox(height: 22),
            Text('بالنشر تؤكد أن الفيديو من صنعك أو لديك حق نشره، ولا يخالف إرشادات المجتمع.',
                textAlign: TextAlign.center, style: E.t(12, c: E.ink3)),
          ]),
        ),
      );

  Widget _form() {
    final c = _ctl!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: _caption, maxLines: 6, minLines: 6, maxLength: 2200,
            decoration: const InputDecoration(hintText: 'اكتب وصفاً… أضف #وسوم ليصل لجمهور أكبر', filled: false,
                border: InputBorder.none, counterText: ''),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => c.value.isPlaying ? c.pause() : c.play(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 110, height: 150, color: Colors.black,
              child: c.value.isInitialized
                  ? FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge,
                      child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)))
                  : const Loading(dark: true),
            ),
          ),
        ),
      ]),
      Row(children: [
        ActionChip(label: const Text('# وسم'), onPressed: _addTag, backgroundColor: E.soft, side: BorderSide.none),
        const SizedBox(width: 8),
        ActionChip(label: const Text('تغيير الفيديو'), onPressed: _busy ? null : () => _pick(ImageSource.gallery), backgroundColor: E.soft, side: BorderSide.none),
      ]),
      const Divider(height: 28),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.lock_open_rounded),
        title: Text('من يمكنه مشاهدة الفيديو', style: E.t(15, w: FontWeight.w600)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(const {'public': 'الجميع', 'friends': 'الأصدقاء', 'private': 'أنا فقط'}[_privacy]!, style: E.t(14, c: E.ink3)),
          const Icon(Icons.chevron_left_rounded, color: E.ink3),
        ]),
        onTap: () async {
          final p = await sheetMenu<String>(context, [
            (Icons.public_rounded, 'الجميع', 'public', false),
            (Icons.people_outline_rounded, 'الأصدقاء (متابعة متبادلة)', 'friends', false),
            (Icons.lock_outline_rounded, 'أنا فقط', 'private', false),
          ]);
          if (p != null) setState(() => _privacy = p);
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.chat_bubble_outline_rounded),
        title: Text('السماح بالتعليقات', style: E.t(15, w: FontWeight.w600)),
        value: _comments, activeColor: E.accent,
        onChanged: (v) => setState(() => _comments = v),
      ),
      if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err, style: E.t(13, c: E.accent))),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Pill('إلغاء', onTap: _busy ? null : () => Navigator.pop(context), height: 50)),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: Pill(_busy ? 'جارٍ النشر…' : 'نشر', primary: true, busy: _busy, icon: Icons.upload_rounded, height: 50, onTap: _publish)),
      ]),
      if (_busy) ...[
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: _prog > 0 ? _prog : null, minHeight: 6, color: E.accent, backgroundColor: E.soft)),
        const SizedBox(height: 6),
        Text('${(_prog * 100).round()}% — لا تغلق الصفحة حتى يكتمل الرفع', textAlign: TextAlign.center, style: E.t(12, c: E.ink3)),
      ],
    ]);
  }
}
