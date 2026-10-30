part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🛡 لوحة الإدارة داخل التطبيق (المالك والمشرفون فقط — كل إجراء محمي في الخادم ومسجَّل)
//   نظرة عامة · الترويج (الوصولات والموافقة) · البلاغات (خلال 24 ساعة — شرط المتاجر) · الأسعار وطرق الدفع
// ════════════════════════════════════════════════════════════════════
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('لوحة الإدارة'),
            bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, indicatorColor: E.ink, labelColor: E.ink,
                unselectedLabelColor: E.ink3, tabs: [Tab(text: 'نظرة عامة'), Tab(text: 'الترويج'), Tab(text: 'البلاغات'), Tab(text: 'الأسعار والدفع')]),
          ),
          body: const TabBarView(children: [_AdminStats(), _AdminPromos(), _AdminReports(), _AdminRates()]),
        ),
      );
}

class _AdminStats extends StatelessWidget {
  const _AdminStats();
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: sb.rpc('admin_stats'),
        builder: (_, s) {
          if (s.hasError) return EmptyState(icon: Icons.lock_outline_rounded, title: 'غير مسموح', sub: errText(s.error!));
          if (!s.hasData) return const Loading();
          final d = Map<String, dynamic>.from(s.data as Map);
          Widget t(String n, String l) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: E.soft, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(n, style: E.t(22, w: FontWeight.w800)),
                  Text(l, style: E.t(12.5, c: E.ink3)),
                ]),
              );
          return GridView.count(
            padding: const EdgeInsets.all(16), crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2,
            children: [
              t(fmtN(d.i('users')), 'المستخدمون (+${d.i('users_today')} اليوم)'),
              t(fmtN(d.i('videos')), 'الفيديوهات (+${d.i('videos_today')} اليوم)'),
              t(fmtN(d.i('views_today')), 'مشاهدات اليوم'),
              t('${d.i('reports_open')}', 'بلاغات مفتوحة'),
              t('${d.i('promos_review')}', 'ترويج بانتظار المراجعة'),
              t('${d.i('promos_active')}', 'ترويج يعمل الآن'),
              t(fmtIqd(d.i('revenue_month')), 'دخل الترويج هذا الشهر'),
            ],
          );
        },
      );
}

class _AdminPromos extends StatefulWidget {
  const _AdminPromos();
  @override
  State<_AdminPromos> createState() => _AdminPromosState();
}

class _AdminPromosState extends State<_AdminPromos> with AutomaticKeepAliveClientMixin {
  String _f = 'review';
  List<Map<String, dynamic>>? _l;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _l = null);
    try {
      final r = await sb.rpc('admin_promos', params: {'p_status': _f});
      _l = [for (final m in (r as List)) Map<String, dynamic>.from(m as Map)];
    } catch (e) {
      _l = [];
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() {});
  }

  Future<void> _receipt(String path) async {
    try {
      final url = await sb.storage.from('receipts').createSignedUrl(path, 300);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => Dialog(
        backgroundColor: Colors.black, insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
      ));
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  Future<void> _op(Map<String, dynamic> c, String op) async {
    var note = '';
    if (op == 'reject' || op == 'unpaid') {
      final t = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: E.card,
        title: Text(op == 'reject' ? 'سبب الرفض' : 'ملاحظة للمستخدم', style: E.t(16, w: FontWeight.w700)),
        content: TextField(controller: t, maxLines: 3, decoration: const InputDecoration(hintText: 'يظهر للمستخدم في الإشعار')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
        ],
      ));
      if (ok != true) return;
      note = t.text.trim();
    }
    try {
      await sb.rpc('admin_promo_set', params: {'p_id': c.i('id'), 'p_op': op, 'p_note': note});
      if (mounted) toast(context, 'تم');
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          for (final f in const [('review', 'للمراجعة'), ('unpaid', 'غير مدفوع'), ('active', 'تعمل'), ('done', 'منتهية')])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(label: Text(f.$2), selected: _f == f.$1, showCheckmark: false, selectedColor: E.ink,
                  labelStyle: E.t(13, w: FontWeight.w700, c: _f == f.$1 ? Colors.white : E.ink),
                  onSelected: (_) { _f = f.$1; _load(); }),
            ),
        ]),
      ),
      Expanded(
        child: _l == null
            ? const Loading()
            : _l!.isEmpty
                ? const EmptyState(icon: Icons.inbox_outlined, title: 'لا شيء هنا')
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _l!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = _l![i];
                        final p = Promo.of(c);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(border: Border.all(color: E.line), borderRadius: BorderRadius.circular(12)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              GestureDetector(
                                onTap: () async {
                                  final v = await Api.video(p.videoId);
                                  if (v != null && context.mounted) VideoListPage.open(context, [v], 0);
                                },
                                child: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 48, height: 64,
                                    child: c.s('poster').isEmpty ? ColoredBox(color: E.soft) : CachedNetworkImage(imageUrl: c.s('poster'), fit: BoxFit.cover))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${c.s('code')} · @${c.s('username')}', style: E.t(13.5, w: FontWeight.w800)),
                                Text('${fmtIqd(p.budget)} · ${fmtN(p.goal)} ${p.clicksGoal ? 'ضغطة' : 'مشاهدة'} · ${p.days} أيام', style: E.t(13, c: E.ink2)),
                                Text('${p.statusLabel} · ${p.payMethod.isEmpty ? '-' : p.payMethod}${c.s('pay_txn').isNotEmpty ? ' · ${c.s('pay_txn')}' : ''}',
                                    style: E.t(12.5, c: p.statusColor)),
                                if (p.status == 'active') Text('${fmtN(p.done)}/${fmtN(p.goal)} · ظهور ${fmtN(p.impressions)}', style: E.t(12.5, c: E.ink3)),
                              ])),
                            ]),
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              if (c.s('pay_receipt').isNotEmpty)
                                OutlinedButton.icon(onPressed: () => _receipt(c.s('pay_receipt')), icon: const Icon(Icons.receipt_long_rounded, size: 16), label: const Text('الوصل')),
                              if (p.status == 'pending') ...[
                                FilledButton(onPressed: () => _op(c, 'approve'), style: FilledButton.styleFrom(backgroundColor: E.ink), child: const Text('موافقة')),
                                OutlinedButton(onPressed: () => _op(c, 'free'), child: const Text('مجاني')),
                                OutlinedButton(onPressed: () => _op(c, 'unpaid'), child: const Text('لم يصل الدفع')),
                                OutlinedButton(onPressed: () => _op(c, 'reject'), child: Text('رفض', style: E.t(13, c: E.accent))),
                              ],
                              if (p.status == 'active') OutlinedButton(onPressed: () => _op(c, 'pause'), child: const Text('إيقاف')),
                              if (p.status == 'paused') OutlinedButton(onPressed: () => _op(c, 'resume'), child: const Text('استئناف')),
                              if (p.status == 'active' || p.status == 'paused')
                                OutlinedButton(onPressed: () => _op(c, 'end'), child: const Text('إنهاء')),
                            ]),
                          ]),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}

class _AdminReports extends StatefulWidget {
  const _AdminReports();
  @override
  State<_AdminReports> createState() => _AdminReportsState();
}

class _AdminReportsState extends State<_AdminReports> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _l;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await sb.rpc('admin_reports', params: {'p_status': 'open'});
      final all = [for (final m in (r as List)) Map<String, dynamic>.from(m as Map)];
      // بلاغ واحد لكل محتوى (مع عدد المبلّغين)
      final seen = <String>{};
      _l = [for (final m in all) if (seen.add('${m['kind']}:${m['target']}')) m];
    } catch (e) {
      _l = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _op(Map<String, dynamic> r, String op) async {
    if (op == 'ban' && !await confirm(context, 'إيقاف الحساب؟', 'يُزال المحتوى ويُوقف الحساب عن النشر والتفاعل.', ok: 'إيقاف', danger: true)) return;
    try {
      await sb.rpc('admin_report_set', params: {'p_id': r.i('id'), 'p_op': op, 'p_note': r.s('reason')});
      if (mounted) toast(context, 'تم');
      _load();
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = _l;
    if (l == null) return const Loading();
    if (l.isEmpty) return const EmptyState(icon: Icons.verified_user_outlined, title: 'لا بلاغات مفتوحة 👌');
    const kinds = {'video': 'فيديو', 'comment': 'تعليق', 'message': 'رسالة', 'user': 'حساب'};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: l.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = l[i];
          final c = r['content'] is Map ? Map<String, dynamic>.from(r['content'] as Map) : <String, dynamic>{};
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: E.line), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${kinds[r.s('kind')] ?? r.s('kind')} · ${r.s('reason')}', style: E.t(14, w: FontWeight.w800)),
                const Spacer(),
                if (r.i('same') > 1) Text('${r.i('same')} بلاغات', style: E.t(12.5, w: FontWeight.w700, c: E.accent)),
              ]),
              const SizedBox(height: 4),
              Text('صاحب المحتوى: @${c.s('username')} · منذ ${ago(r.d('created_at'))}', style: E.t(12.5, c: E.ink3)),
              if (c.s('body').isNotEmpty || c.s('caption').isNotEmpty || c.s('bio').isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10), width: double.infinity,
                  decoration: BoxDecoration(color: E.soft, borderRadius: BorderRadius.circular(8)),
                  child: Text(c.s('body').isNotEmpty ? c.s('body') : c.s('caption').isNotEmpty ? c.s('caption') : c.s('bio'), style: E.t(13.5)),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (r.s('kind') == 'video')
                  OutlinedButton.icon(onPressed: () async {
                    final v = await Api.video(r.s('target'));
                    if (v != null && context.mounted) VideoListPage.open(context, [v], 0);
                  }, icon: const Icon(Icons.play_arrow_rounded, size: 16), label: const Text('مشاهدة')),
                if (c.s('user_id').isNotEmpty)
                  OutlinedButton(onPressed: () => UserPage.open(context, c.s('user_id')), child: const Text('الحساب')),
                if (r.s('kind') != 'user') FilledButton(onPressed: () => _op(r, 'remove'), style: FilledButton.styleFrom(backgroundColor: E.ink), child: const Text('إزالة')),
                OutlinedButton(onPressed: () => _op(r, 'ban'), child: Text('إيقاف الحساب', style: E.t(13, c: E.accent))),
                OutlinedButton(onPressed: () => _op(r, 'dismiss'), child: const Text('لا مخالفة')),
              ]),
            ]),
          );
        },
      ),
    );
  }
}

class _AdminRates extends StatefulWidget {
  const _AdminRates();
  @override
  State<_AdminRates> createState() => _AdminRatesState();
}

class _AdminRatesState extends State<_AdminRates> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _m;
  final Map<String, TextEditingController> _c = {};
  List<Map<String, dynamic>> _methods = [];
  bool _enabled = true, _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await PromoApi.rates();
    _m = r.m;
    _enabled = r.enabled;
    for (final k in ['cpm', 'cpc', 'min_budget', 'max_budget', 'bonus_first', 'max_days', 'usd']) {
      _c[k] = TextEditingController(text: '${r.m[k] ?? ''}');
    }
    _c['packages'] = TextEditingController(text: r.packages.join(', '));
    _methods = r.methods;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final v = Map<String, dynamic>.from(_m ?? {});
    v['enabled'] = _enabled;
    for (final k in ['cpm', 'cpc', 'min_budget', 'max_budget', 'bonus_first', 'max_days', 'usd']) {
      v[k] = int.tryParse(_c[k]!.text.trim()) ?? v[k];
    }
    v['packages'] = [for (final x in _c['packages']!.text.split(RegExp(r'[,،\s]+'))) if (int.tryParse(x) != null) int.parse(x)];
    v['methods'] = _methods;
    try {
      await sb.rpc('admin_setting', params: {'p_key': 'promo_rates', 'p_value': v});
      if (mounted) toast(context, 'حُفظ ✓');
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _editMethod([int? i]) async {
    final m = i == null ? <String, dynamic>{} : _methods[i];
    final n = TextEditingController(text: m.s('name')), a = TextEditingController(text: m.s('account')), h = TextEditingController(text: m.s('holder'));
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: E.card,
      title: Text(i == null ? 'طريقة دفع جديدة' : 'تعديل', style: E.t(16, w: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(hintText: 'الاسم — مثال: زين كاش')),
        const SizedBox(height: 8),
        TextField(controller: a, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: 'رقم الحساب / الهاتف')),
        const SizedBox(height: 8),
        TextField(controller: h, decoration: const InputDecoration(hintText: 'اسم صاحب الحساب (اختياري)')),
      ]),
      actions: [
        if (i != null) TextButton(onPressed: () { setState(() => _methods.removeAt(i)); Navigator.pop(ctx, false); }, child: Text('حذف', style: E.t(14, c: E.accent))),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
      ],
    ));
    if (ok != true || n.text.trim().isEmpty) return;
    final v = {'name': n.text.trim(), 'account': a.text.trim(), 'holder': h.text.trim()};
    setState(() => i == null ? _methods.add(v) : _methods[i] = v);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_m == null) return const Loading();
    if (Me.profile?.admin != true) return const EmptyState(icon: Icons.lock_outline_rounded, title: 'للمدير فقط');
    Widget f(String k, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: _c[k], keyboardType: k == 'packages' ? TextInputType.text : TextInputType.number,
              decoration: InputDecoration(labelText: label)),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('استقبال طلبات الترويج'), value: _enabled, activeColor: E.accent,
          onChanged: (v) => setState(() => _enabled = v)),
      f('cpm', 'السعر لكل 1000 مشاهدة (د.ع)'),
      f('cpc', 'السعر لكل ضغطة (د.ع)'),
      f('min_budget', 'أقل ميزانية'),
      f('max_budget', 'أعلى ميزانية'),
      f('bonus_first', 'هدية أول ترويج (%)'),
      f('max_days', 'أطول مدة (يوم)'),
      f('usd', 'سعر الدولار (د.ع)'),
      f('packages', 'الباقات (مفصولة بفاصلة)'),
      const SizedBox(height: 8),
      Row(children: [
        Text('طرق الدفع', style: E.t(16, w: FontWeight.w800)),
        const Spacer(),
        TextButton.icon(onPressed: () => _editMethod(), icon: const Icon(Icons.add_rounded), label: const Text('إضافة')),
      ]),
      for (int i = 0; i < _methods.length; i++)
        ListTile(contentPadding: EdgeInsets.zero, title: Text(_methods[i].s('name')),
            subtitle: Text('${_methods[i].s('account')} ${_methods[i].s('holder')}'), trailing: const Icon(Icons.edit_outlined), onTap: () => _editMethod(i)),
      const SizedBox(height: 16),
      Pill('حفظ', primary: true, busy: _busy, onTap: _save, height: 48),
    ]);
  }
}
