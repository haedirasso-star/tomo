part of '../main.dart';

/// حملة ترويج (من نظام إعلانات TOTV)
class Promo {
  final int id, budget, price, bonusPct, goal, days;
  final String videoId, objective, ctaLabel, ctaLink, status, payStatus, payMethod, reason;
  final int impressions, views, paidViews, uniq, completes, clicks, paidClicks, watchMs, skips;
  final DateTime? created, startAt, endAt, doneAt, paidAt;
  final Map<String, dynamic> raw;
  const Promo({
    required this.id, required this.budget, required this.price, required this.bonusPct, required this.goal, required this.days,
    required this.videoId, required this.objective, required this.ctaLabel, required this.ctaLink, required this.status,
    required this.payStatus, required this.payMethod, required this.reason, required this.impressions, required this.views,
    required this.paidViews, required this.uniq, required this.completes, required this.clicks, required this.paidClicks,
    required this.watchMs, required this.skips, this.created, this.startAt, this.endAt, this.doneAt, this.paidAt, this.raw = const {},
  });

  factory Promo.of(Map<String, dynamic> m) => Promo(
        id: m.i('id'), budget: m.i('budget'), price: m.i('price'), bonusPct: m.i('bonus_pct'), goal: m.i('goal'), days: m.i('days'),
        videoId: m.s('video_id'), objective: m.s('objective'), ctaLabel: m.s('cta_label'), ctaLink: m.s('cta_link'),
        status: m.s('status'), payStatus: m.s('pay_status'), payMethod: m.s('pay_method'), reason: m.s('reason'),
        impressions: m.i('impressions'), views: m.i('views'), paidViews: m.i('paid_views'), uniq: m.i('uniq'),
        completes: m.i('completes'), clicks: m.i('clicks'), paidClicks: m.i('paid_clicks'), watchMs: m.i('watch_ms'),
        skips: m.i('skips'), created: m.d('created_at'), startAt: m.d('start_at'), endAt: m.d('end_at'), doneAt: m.d('done_at'),
        paidAt: m.d('paid_at'), raw: m,
      );

  String get code => 'TO-P-${id.toString().padLeft(6, '0')}';
  bool get clicksGoal => objective == 'clicks';
  int get done => clicksGoal ? paidClicks : paidViews;
  double get progress => goal <= 0 ? 0 : (done / goal).clamp(0, 1).toDouble();
  double get ctr => views > 0 ? clicks * 100 / views : 0;
  double get completeRate => views > 0 ? completes * 100 / views : 0;
  double get avgWatch => views > 0 ? watchMs / views / 1000 : 0;
  bool get needsPay => status == 'pending' && payStatus == 'unpaid';

  String get statusLabel {
    switch (status) {
      case 'pending': return payStatus == 'unpaid' ? 'بانتظار الدفع' : 'قيد المراجعة';
      case 'approved': return 'يبدأ قريباً';
      case 'active': return 'يعمل الآن';
      case 'paused': return 'متوقف مؤقتاً';
      case 'done': return 'اكتمل';
      case 'rejected': return 'مرفوض';
      case 'cancelled': return 'ملغى';
    }
    return status;
  }

  Color get statusColor {
    switch (status) {
      case 'active': return const Color(0xFF16A34A);
      case 'pending': return payStatus == 'unpaid' ? const Color(0xFFD97706) : const Color(0xFF2563EB);
      case 'done': return const Color(0xFF7C3AED);
      case 'rejected': case 'cancelled': return const Color(0xFFDC2626);
    }
    return E.ink3;
  }
}

class PromoRates {
  final Map<String, dynamic> m;
  const PromoRates(this.m);
  int _i(String k, int d) => (m[k] as num?)?.toInt() ?? int.tryParse('${m[k] ?? ''}') ?? d;
  bool get enabled => m['enabled'] != false;
  int get cpm => _i('cpm', 1000);
  int get cpc => _i('cpc', 150);
  int get minBudget => _i('min_budget', 5000);
  int get maxBudget => _i('max_budget', 5000000);
  int get bonusFirst => _i('bonus_first', 30);
  int get maxDays => _i('max_days', 30);
  int get usd => _i('usd', 1450);
  List<int> get packages => [for (final p in (m['packages'] as List? ?? const [5000, 10000, 25000, 50000])) (p as num).toInt()];
  List<Map<String, dynamic>> get methods => [for (final x in (m['methods'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
  int estimate(String objective, int budget, int bonusPct) {
    final price = objective == 'clicks' ? cpc : cpm;
    if (price <= 0) return 0;
    final base = objective == 'clicks' ? budget / price : budget * 1000 / price;
    return (base * (1 + bonusPct / 100)).floor();
  }
}

String fmtIqd(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b د.ع';
}

class PromoApi {
  PromoApi._();

  static Future<PromoRates> rates() async => PromoRates(Map<String, dynamic>.from((await sb.rpc('promo_rates')) as Map? ?? {}));

  static Future<bool> isFirst() async {
    final r = await sb.from('promo_campaigns').select('id').eq('user_id', myId!).not('status', 'in', '(cancelled,rejected)').limit(1);
    return r.isEmpty;
  }

  static Future<Promo> create({required String videoId, required String objective, required int budget, required int days,
      String ctaLabel = '', String ctaLink = ''}) async {
    final r = await sb.rpc('promo_create', params: {
      'p_video': videoId, 'p_objective': objective, 'p_budget': budget, 'p_days': days,
      'p_cta_label': ctaLabel, 'p_cta_link': ctaLink,
    });
    return Promo.of(Map<String, dynamic>.from(r as Map));
  }

  /// صورة الوصل ⇐ مخزن receipts الخاص (لا يراها إلا صاحبها والمشرفون) ⇐ إرسال للمراجعة
  static Future<void> pay(Promo p, {required String method, required io.File receipt, String txn = ''}) async {
    final path = '${myId!}/p${p.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await sb.storage.from('receipts').upload(path, receipt, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    await sb.rpc('promo_pay', params: {'p_id': p.id, 'p_method': method, 'p_receipt': path, 'p_txn': txn});
    // إشعار فوري لتطبيق إدارة TOTV (الطلبات موحّدة هناك)
    unawaited(Api.fn('promo_notify', {'id': p.id}).then((_) {}, onError: (_) {}));
  }

  static Future<List<Promo>> mine() async {
    final r = await sb.from('promo_campaigns').select().eq('user_id', myId!).order('created_at', ascending: false).limit(100);
    return [for (final m in r) Promo.of(m)];
  }

  static Future<Promo?> get(int id) async {
    final r = await sb.from('promo_campaigns').select().eq('id', id).maybeSingle();
    return r == null ? null : Promo.of(r);
  }

  static Future<List<Map<String, dynamic>>> daily(int id) async =>
      List<Map<String, dynamic>>.from(await sb.from('promo_daily').select().eq('cid', id).order('day').limit(60));

  static Future<void> cancel(int id) => sb.rpc('promo_cancel', params: {'p_id': id});
  static Future<void> pause(int id, bool on) => sb.rpc('promo_pause', params: {'p_id': id, 'p_on': on});
}
