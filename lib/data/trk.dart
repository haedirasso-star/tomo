part of '../main.dart';

/// عدّادات دقيقة بلا ضغط على الخادم: كل جهاز يجمع أحداثه ويرسلها دفعة واحدة كل دقيقة ونصف
///  v مشاهدة (u=1 أول مرة اليوم على هذا الجهاز) · q إكمال · w زمن المشاهدة (ms) · s مشاركة
class Trk with WidgetsBindingObserver {
  Trk._();
  static final _i = Trk._();
  static final List<Map<String, dynamic>> _q = [];
  static Timer? _t;
  static bool _sending = false;
  static String _day = '';
  /// معرّف عشوائي للجهاز (لا يكشف الهوية) — يمنع احتساب المشاهدة المدفوعة أكثر من 3 مرات يومياً من نفس الجهاز
  static String _dev = '';
  static Set<String> _seenToday = {};

  /// ما شاهده الجهاز مؤخراً (لا يتكرر في «لك»)
  static final List<String> recent = [];

  static void init() {
    WidgetsBinding.instance.addObserver(_i);
    _day = Prefs.p.getString('trk_day') ?? '';
    _dev = Prefs.p.getString('trk_dev') ?? '';
    if (_dev.isEmpty) {
      final r = math.Random.secure();
      _dev = 'd${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
      Prefs.p.setString('trk_dev', _dev);
    }
    _seenToday = (Prefs.p.getStringList('trk_seen') ?? const []).toSet();
    recent.addAll(Prefs.p.getStringList('trk_recent') ?? const []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) unawaited(flush());
  }

  static String get _today {
    final b = DateTime.now().toUtc().add(const Duration(hours: 3));
    return '${b.year}-${b.month}-${b.day}';
  }

  /// t: i ظهور · v مشاهدة · q إكمال · w زمن · s مشاركة · c ضغطة زر الإعلان · k تخطٍّ — cid للفيديو الممول
  static void ev(String t, String video, {int ms = 0, int cid = 0}) {
    if (video.isEmpty) return;
    final e = <String, dynamic>{'t': t, 'r': video};
    if (cid > 0) e['c'] = cid;
    if (t == 'w') {
      if (ms < 300) return;
      e['w'] = ms;
    }
    if (t == 'v') {
      final d = _today;
      if (d != _day) { _day = d; _seenToday = {}; }
      if (_seenToday.add(video)) e['u'] = 1;
      recent.remove(video);
      recent.insert(0, video);
      if (recent.length > 300) recent.removeRange(300, recent.length);
      unawaited(_save());
    }
    _q.add(e);
    if (_q.length >= 120) { unawaited(flush()); return; }
    _t ??= Timer(const Duration(seconds: 90), () => unawaited(flush()));
  }

  static Future<void> _save() async {
    await Prefs.p.setString('trk_day', _day);
    await Prefs.p.setStringList('trk_seen', _seenToday.take(2000).toList());
    await Prefs.p.setStringList('trk_recent', recent);
  }

  static Future<void> flush() async {
    _t?.cancel();
    _t = null;
    if (_q.isEmpty || _sending) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_q.take(250));
    _q.removeRange(0, batch.length);
    try {
      await sb.rpc('trk', params: {'p': {'d': _dev, 'e': batch}}).timeout(const Duration(seconds: 12));
    } catch (_) {
      if (_q.length < 600) _q.insertAll(0, batch);
    }
    _sending = false;
    if (_q.isNotEmpty) _t ??= Timer(const Duration(seconds: 90), () => unawaited(flush()));
  }
}
