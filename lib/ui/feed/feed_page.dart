part of '../../main.dart';

/// الرئيسية: تمرير عمودي بملء الشاشة — «لك» (الخوارزمية) و«أتابعهم»
///  السلاسة (من محرك الريلز المجرَّب): مشغّل للحالي + السابق + التاليين فقط، والتاليان يُنزَّلان كاملين للكاش
///  قبل الوصول إليهما ⇐ بدء فوري · فيديو معطوب ⇐ تخطٍّ تلقائي · الخروج من التطبيق يوقف الفيديو
class FeedPage extends StatefulWidget {
  final bool active;
  const FeedPage({super.key, this.active = true});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  String _mode = 'for';
  bool _followingBuilt = false;
  final _keys = {'for': GlobalKey<VideoPagerState>(), 'following': GlobalKey<VideoPagerState>()};

  void _setMode(String m) {
    if (m == _mode) {
      _keys[m]?.currentState?.refresh();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() { _mode = m; if (m == 'following') _followingBuilt = true; });
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
        child: Stack(children: [
          // كل وضع له مشغّلاته — المخفي متوقف
          Offstage(offstage: _mode != 'for', child: VideoPager(key: _keys['for'], source: FeedSource.forYou(), active: widget.active && _mode == 'for')),
          if (_followingBuilt)
            Offstage(offstage: _mode != 'following', child: VideoPager(key: _keys['following'], source: FeedSource.following(), active: widget.active && _mode == 'following')),
          PositionedDirectional(
            top: 0, start: 0, end: 0,
            child: SafeArea(
              child: SizedBox(
                height: 48,
                child: Stack(alignment: Alignment.center, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _tab('following', 'أتابعهم'),
                    const SizedBox(width: 22),
                    _tab('for', 'لك'),
                  ]),
                  PositionedDirectional(
                    end: 8,
                    child: IconButton(
                      icon: const Icon(Icons.search_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );

  Widget _tab(String m, String label) {
    final sel = _mode == m;
    return GestureDetector(
      onTap: () async {
        if (m == 'following' && !Me.signedIn) {
          if (!await Me.ensure(context)) return;
        }
        _setMode(m);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: E.t(17, w: sel ? FontWeight.w800 : FontWeight.w600, c: sel ? Colors.white : Colors.white70).copyWith(
            shadows: const [Shadow(blurRadius: 6, color: Colors.black45)])),
        const SizedBox(height: 4),
        AnimatedContainer(duration: const Duration(milliseconds: 180), width: sel ? 26 : 0, height: 3,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
      ]),
    );
  }
}

/// مصدر قائمة فيديوهات قابلة للتمديد بلا نهاية
class FeedSource {
  final Future<List<Video>> Function(List<Video> current) more;
  final String empty;
  FeedSource(this.more, {this.empty = 'لا توجد فيديوهات بعد'});

  factory FeedSource.forYou() => FeedSource(
        (cur) => Api.forYou(seen: [...cur.map((v) => v.id), ...Trk.recent]),
        empty: 'لا فيديوهات جديدة الآن — انشر أول فيديو!',
      );
  factory FeedSource.following() => FeedSource(
        (cur) => Api.following(before: cur.isEmpty ? null : cur.last.created),
        empty: 'تابع حسابات لترى فيديوهاتها هنا',
      );
  /// قائمة ثابتة (من الملف الشخصي أو المحفوظات) تبدأ من فيديو معيّن
  factory FeedSource.fixed(List<Video> list) {
    var given = false;
    return FeedSource((cur) async {
      if (given) return <Video>[];
      given = true;
      return list;
    });
  }
}

/// مشغّل الصفحات العمودي — يُستخدم في الرئيسية وعند فتح فيديو من ملف شخصي
class VideoPager extends StatefulWidget {
  final FeedSource source;
  final bool active;
  final int start;
  final bool showBack;
  const VideoPager({super.key, required this.source, this.active = true, this.start = 0, this.showBack = false});
  @override
  State<VideoPager> createState() => VideoPagerState();
}

class VideoPagerState extends State<VideoPager> with WidgetsBindingObserver {
  late final PageController _pc = PageController(initialPage: widget.start);
  final List<Video> _l = [];
  final Map<int, VideoPlayerController> _ctl = {};
  final Set<int> _bad = {}, _making = {};
  late int _i = widget.start;
  bool _loading = true, _more = true, _paused = false, _fetching = false;
  String _err = '';
  Timer? _skipT;
  // إشارات المشاهدة للفيديو الحالي
  DateTime _shownAt = DateTime.now();
  Duration _watched = Duration.zero, _lastPos = Duration.zero;
  bool _completed = false;
  VideoPlayerController? _tracked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(first: true);
    if (widget.active && !kIsWeb) WakelockPlus.enable();
  }

  @override
  void didUpdateWidget(covariant VideoPager old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) {
        _shownAt = DateTime.now();
        if (!_paused) _ctl[_i]?.play();
        if (!kIsWeb) WakelockPlus.enable();
      } else {
        _record();
        _ctl[_i]?.pause();
        if (!kIsWeb) WakelockPlus.disable();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _record();
    _tracked?.removeListener(_track);
    _skipT?.cancel();
    for (final c in _ctl.values) { c.dispose(); }
    _pc.dispose();
    if (!kIsWeb) WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = _ctl[_i];
    if (c == null) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      c.pause();
    } else if (s == AppLifecycleState.resumed && !_paused && widget.active) {
      c.play();
    }
  }

  Future<void> refresh() async {
    for (final c in _ctl.values) { c.dispose(); }
    _ctl.clear();
    _bad.clear();
    _l.clear();
    _i = 0;
    _more = true;
    if (_pc.hasClients) _pc.jumpToPage(0);
    setState(() => _loading = true);
    await _load(first: true);
  }

  Future<void> _load({bool first = false}) async {
    if (_fetching || !_more) return;
    _fetching = true;
    try {
      final got = await widget.source.more(_l);
      final have = _l.map((v) => v.id).toSet();
      final fresh = got.where((v) => !have.contains(v.id)).toList();
      if (fresh.isEmpty) _more = false;
      _l.addAll(fresh);
      _err = '';
    } catch (e) {
      _err = errText(e);
    }
    _fetching = false;
    if (!mounted) return;
    setState(() => _loading = false);
    if (first) _shownAt = DateTime.now();
    _sync();
    if (first && _l.isNotEmpty) _view(_l[_i]);
  }

  Set<int> get _window => {for (int k = _i - 1; k <= _i + 2; k++) if (k >= 0 && k < _l.length) k};

  void _sync() {
    final w = _window;
    for (final k in _ctl.keys.where((k) => !w.contains(k)).toList()) {
      _ctl.remove(k)?.dispose();
    }
    for (final k in [_i, _i + 1, ...w.where((k) => k != _i && k != _i + 1)]) {
      if (w.contains(k) && !_ctl.containsKey(k) && !_bad.contains(k)) _make(k);
    }
    for (int k = _i + 3; k <= _i + 4 && k < _l.length; k++) {
      unawaited(VideoCache.fetch(_l[k].url));
    }
    _ctl.forEach((k, c) {
      if (!c.value.isInitialized) return;
      if (k == _i && widget.active) {
        if (!_paused) c.play();
        _attach(c);
      } else {
        c.pause();
        if (k != _i && c.value.position > Duration.zero) c.seekTo(Duration.zero);
      }
    });
  }

  void _make(int k) {
    final v = _l[k];
    if (!_making.add(k)) {
      if (k == _i && !_ctl.containsKey(k)) _makeCtl(k, null);
      return;
    }
    () async {
      io.File? f = await VideoCache.cached(v.url);
      if (f == null && k != _i) f = await VideoCache.fetch(v.url);
      _making.remove(k);
      if (!mounted || _ctl.containsKey(k) || k >= _l.length || _l[k].id != v.id || !_window.contains(k) || _bad.contains(k)) return;
      _makeCtl(k, f);
    }();
  }

  void _makeCtl(int k, io.File? file) {
    final v = _l[k];
    final c = file != null
        ? VideoPlayerController.file(file, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false))
        : VideoPlayerController.networkUrl(Uri.parse(v.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    _ctl[k] = c;
    c.setLooping(true);
    c.initialize().then((_) {
      if (!mounted || _ctl[k] != c) return;
      if (k == _i && !_paused && widget.active) {
        c.play();
        _attach(c);
      }
      setState(() {});
    }).catchError((Object e) {
      debugPrint('[feed] $k: $e');
      if (!mounted || _ctl[k] != c) return;
      _ctl.remove(k);
      c.dispose();
      setState(() => _bad.add(k));
      if (k == _i) _autoSkip();
    });
  }

  void _autoSkip() {
    _skipT?.cancel();
    _skipT = Timer(const Duration(milliseconds: 2000), () {
      if (mounted && _bad.contains(_i) && _i + 1 < _l.length) {
        _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  void _attach(VideoPlayerController c) {
    if (_tracked == c) return;
    _tracked?.removeListener(_track);
    _tracked = c;
    _lastPos = Duration.zero;
    c.addListener(_track);
  }

  /// إكمال = وصل للنهاية مرة واحدة على الأقل (التكرار يعود للبداية)
  void _track() {
    final c = _tracked;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position, dur = c.value.duration;
    if (!_completed && dur > Duration.zero &&
        (pos >= dur - const Duration(milliseconds: 400) ||
            (pos + const Duration(milliseconds: 900) < _lastPos && _lastPos > dur - const Duration(milliseconds: 1500)))) {
      _completed = true;
      if (_i < _l.length) Trk.ev('q', _l[_i].id, cid: _l[_i].cid);
    }
    _lastPos = pos;
  }

  void _record() {
    if (_i < 0 || _i >= _l.length) return;
    final ms = (_watched + (_paused || !widget.active ? Duration.zero : DateTime.now().difference(_shownAt))).inMilliseconds;
    Trk.ev('w', _l[_i].id, ms: ms, cid: _l[_i].cid);
  }

  void _onPage(int i) {
    _record();
    _shownAt = DateTime.now();
    _watched = Duration.zero;
    _completed = false;
    setState(() { _i = i; _paused = false; });
    HapticFeedback.selectionClick();
    _sync();
    _view(_l[i]);
    if (i >= _l.length - 3) _load();
    if (_bad.contains(i)) _autoSkip();
  }

  void _view(Video v) {
    if (v.cid > 0) Trk.ev('i', v.id, cid: v.cid);
    Trk.ev('v', v.id, cid: v.cid);
  }

  void _togglePause() {
    final c = _ctl[_i];
    if (c == null || !c.value.isInitialized) return;
    setState(() => _paused = !_paused);
    if (_paused) {
      _watched += DateTime.now().difference(_shownAt);
      c.pause();
    } else {
      _shownAt = DateTime.now();
      c.play();
    }
  }

  /// يوقف الفيديو أثناء فتح صفحة أخرى ثم يكمله
  Future<T?> pauseDuring<T>(Future<T?> Function() f) async {
    final c = _ctl[_i];
    final was = !_paused;
    c?.pause();
    final r = await f();
    if (mounted && was && widget.active) c?.play();
    return r;
  }

  void removeAt(String id) {
    final k = _l.indexWhere((v) => v.id == id);
    if (k < 0) return;
    for (final c in _ctl.values) { c.dispose(); }
    _ctl.clear();
    _bad.clear();
    setState(() {
      _l.removeAt(k);
      if (_i >= _l.length) _i = math.max(0, _l.length - 1);
    });
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading && _l.isEmpty) {
      body = const Loading(dark: true);
    } else if (_l.isEmpty) {
      body = EmptyState(
        dark: true,
        icon: Icons.video_library_outlined,
        title: _err.isNotEmpty ? 'تعذّر التحميل' : widget.source.empty,
        sub: _err,
        action: TextButton(onPressed: refresh, child: Text('تحديث', style: E.t(15, w: FontWeight.w700, c: Colors.white))),
      );
    } else {
      body = RefreshIndicator(
        color: Colors.white, backgroundColor: Colors.black, edgeOffset: 80,
        onRefresh: refresh,
        child: PageView.builder(
          controller: _pc,
          scrollDirection: Axis.vertical,
          itemCount: _l.length,
          onPageChanged: _onPage,
          itemBuilder: (_, k) => VideoView(
            key: ValueKey(_l[k].id),
            video: _l[k],
            ctl: _ctl[k],
            broken: _bad.contains(k),
            paused: k == _i && _paused,
            onTap: _togglePause,
            onRetry: () { setState(() => _bad.remove(k)); _sync(); },
            pager: this,
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(children: [
        Positioned.fill(child: body),
        if (widget.showBack)
          PositionedDirectional(top: 0, start: 0, child: SafeArea(child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).maybePop(),
          ))),
      ]),
    );
  }
}
