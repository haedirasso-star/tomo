part of '../main.dart';

// ════════════════════════════════════════════════════════════════════
//  🔥 الترويج — من «أعلن معنا» في TOTV بنفس المنطق المجرَّب (أسود وأبيض · خطوات · دفع بنكي)
//   PromotePage    ⇐ 3 خطوات: الميزانية والهدف ⇐ الزر والمدة ⇐ المراجعة
//   PromotePayPage ⇐ المبلغ والرمز · طرق الدفع مع نسخ · صورة الوصل · تأكيد
//   MyPromosPage   ⇐ ترويجاتي · PromoDetailPage ⇐ الأرقام الدقيقة يومياً + الوصل الرسمي
// ════════════════════════════════════════════════════════════════════

class _Box extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Box({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: E.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: E.line)),
        child: child,
      );
}

Widget _kv(String k, String v, {bool bold = false, Color? c}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(k, style: E.t(14, c: E.ink3))),
        Text(v, style: E.t(14.5, w: bold ? FontWeight.w800 : FontWeight.w600, c: c ?? E.ink)),
      ]),
    );

/// زر «روّج» — يُعرض تحت فيديوهاتي وفي ملفي الشخصي
Future<void> openPromote(BuildContext context, Video v) async {
  if (!await Me.ensure(context) || !context.mounted) return;
  if (v.userId != myId) return;
  if (v.privacy != 'public' || v.status != 'ready') {
    toast(context, 'اجعل الفيديو «للجميع» أولاً ثم روّجه');
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PromotePage(video: v)));
}

class PromotePage extends StatefulWidget {
  final Video video;
  const PromotePage({super.key, required this.video});
  @override
  State<PromotePage> createState() => _PromotePageState();
}

class _PromotePageState extends State<PromotePage> {
  PromoRates? _r;
  bool _first = false, _busy = false;
  String _err = '';
  int _step = 0, _budget = 10000, _days = 7;
  String _objective = 'views';
  final _label = TextEditingController(), _link = TextEditingController(), _custom = TextEditingController();
  static const _labels = ['اطلب الآن', 'زيارة الموقع', 'تواصل معنا', 'تابعني', 'حمّل التطبيق'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_label, _link, _custom]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await PromoApi.rates();
      _first = await PromoApi.isFirst();
      _r = r;
      if (r.packages.isNotEmpty && !r.packages.contains(_budget)) _budget = r.packages.length > 1 ? r.packages[1] : r.packages.first;
    } catch (e) {
      _err = errText(e);
    }
    if (mounted) setState(() {});
  }

  int get _bonus => _first ? (_r?.bonusFirst ?? 0) : 0;

  Future<void> _submit() async {
    setState(() { _busy = true; _err = ''; });
    try {
      final p = await PromoApi.create(
        videoId: widget.video.id, objective: _objective, budget: _budget, days: _days,
        ctaLabel: _link.text.trim().isEmpty ? '' : (_label.text.trim().isEmpty ? 'اعرف المزيد' : _label.text.trim()),
        ctaLink: _link.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PromotePayPage(promo: p, rates: _r!)));
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e); });
    }
  }

  void _next() {
    final r = _r!;
    if (_step == 0 && (_budget < r.minBudget || _budget > r.maxBudget)) {
      setState(() => _err = 'الميزانية بين ${fmtIqd(r.minBudget)} و ${fmtIqd(r.maxBudget)}');
      return;
    }
    if (_step == 1 && _objective == 'clicks' && _link.text.trim().isEmpty) {
      setState(() => _err = 'الدفع بالضغطة يحتاج رابطاً للزر');
      return;
    }
    setState(() { _err = ''; _step++; });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      backgroundColor: E.page,
      appBar: AppBar(
        backgroundColor: E.page,
        title: const Text('ترويج الفيديو'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _step > 0 ? setState(() => _step--) : Navigator.pop(context)),
      ),
      body: r == null
          ? (_err.isEmpty ? const Loading() : EmptyState(icon: Icons.error_outline_rounded, title: 'تعذّر التحميل', sub: _err))
          : !r.enabled
              ? const EmptyState(icon: Icons.pause_circle_outline_rounded, title: 'الترويج متوقف مؤقتاً', sub: 'عد لاحقاً')
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Row(children: [
                      for (int i = 0; i < 3; i++) Expanded(child: Container(
                        height: 4, margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: i <= _step ? E.ink : E.line, borderRadius: BorderRadius.circular(2)))),
                    ]),
                  ),
                  Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
                    if (_step == 0) ..._stepBudget(r),
                    if (_step == 1) ..._stepButton(r),
                    if (_step == 2) ..._stepReview(r),
                    if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err, style: E.t(13, c: E.accent))),
                  ])),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SizedBox(width: double.infinity, child: _step < 2
                          ? _blackPill('التالي', _next)
                          : _blackPill('تأكيد والانتقال للدفع', _busy ? null : _submit, busy: _busy)),
                    ),
                  ),
                ]),
    );
  }

  List<Widget> _stepBudget(PromoRates r) {
    final est = r.estimate(_objective, _budget, _bonus);
    return [
      _Box(child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 54, height: 72,
            child: widget.video.poster.isEmpty ? ColoredBox(color: E.soft)
                : CachedNetworkImage(imageUrl: widget.video.poster, fit: BoxFit.cover))),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.video.caption.isEmpty ? 'فيديوك' : widget.video.caption, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: E.t(14, w: FontWeight.w600))),
      ])),
      const SizedBox(height: 14),
      Text('ماذا تريد؟', style: E.t(16, w: FontWeight.w800)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _choice('مشاهدات أكثر', '${fmtIqd(r.cpm)} لكل 1000 مشاهدة', _objective == 'views', () => setState(() => _objective = 'views'))),
        const SizedBox(width: 10),
        Expanded(child: _choice('زيارات لرابطي', '${fmtIqd(r.cpc)} لكل ضغطة', _objective == 'clicks', () => setState(() => _objective = 'clicks'))),
      ]),
      const SizedBox(height: 18),
      Text('الميزانية', style: E.t(16, w: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in r.packages)
          ChoiceChip(
            label: Text(fmtIqd(p)), selected: _budget == p, showCheckmark: false,
            selectedColor: E.ink, labelStyle: E.t(14, w: FontWeight.w700, c: _budget == p ? Colors.white : E.ink),
            backgroundColor: E.card, side: BorderSide(color: E.line),
            onSelected: (_) => setState(() { _budget = p; _custom.clear(); }),
          ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _custom, keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(hintText: 'مبلغ آخر (د.ع)', fillColor: E.card,
            helperText: 'أقل مبلغ ${fmtIqd(r.minBudget)} — تقريباً \$${(_budget / r.usd).toStringAsFixed(1)}'),
        onChanged: (t) { final n = int.tryParse(t); if (n != null) setState(() => _budget = n); },
      ),
      const SizedBox(height: 14),
      _Box(child: Column(children: [
        Text('الوصول المتوقع', style: E.t(13.5, c: E.ink3)),
        const SizedBox(height: 4),
        Text('${fmtN(est)} ${_objective == 'clicks' ? 'ضغطة' : 'مشاهدة'}', style: E.t(28, w: FontWeight.w800)),
        if (_bonus > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: E.ink, borderRadius: BorderRadius.circular(20)),
            child: Text('🎁 أول ترويج: +$_bonus% هدية', style: E.t(12.5, w: FontWeight.w700, c: Colors.white)),
          ),
        ],
      ])),
    ];
  }

  List<Widget> _stepButton(PromoRates r) => [
        Text('زر تحت الفيديو (اختياري)', style: E.t(16, w: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('يأخذ المشاهد إلى موقعك أو متجرك أو صفحتك', style: E.t(13, c: E.ink3)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in _labels)
            ChoiceChip(
              label: Text(l), selected: _label.text == l, showCheckmark: false,
              selectedColor: E.ink, labelStyle: E.t(13.5, w: FontWeight.w700, c: _label.text == l ? Colors.white : E.ink),
              backgroundColor: E.card, side: BorderSide(color: E.line),
              onSelected: (_) => setState(() => _label.text = l),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _link, keyboardType: TextInputType.url, textDirection: TextDirection.ltr,
            decoration: InputDecoration(hintText: 'https://example.com', fillColor: E.card)),
        const SizedBox(height: 22),
        Text('المدة', style: E.t(16, w: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in [3, 7, 14, 30].where((d) => d <= r.maxDays))
            ChoiceChip(
              label: Text('$d أيام'), selected: _days == d, showCheckmark: false,
              selectedColor: E.ink, labelStyle: E.t(13.5, w: FontWeight.w700, c: _days == d ? Colors.white : E.ink),
              backgroundColor: E.card, side: BorderSide(color: E.line),
              onSelected: (_) => setState(() => _days = d),
            ),
        ]),
        const SizedBox(height: 8),
        Text('ينتهي الترويج عند بلوغ الهدف أو انتهاء المدة — أيهما أسبق.', style: E.t(12.5, c: E.ink3)),
      ];

  List<Widget> _stepReview(PromoRates r) {
    final est = r.estimate(_objective, _budget, _bonus);
    return [
      _Box(child: Column(children: [
        _kv('الهدف', _objective == 'clicks' ? 'زيارات لرابطي' : 'مشاهدات أكثر'),
        _kv('الوصول المتوقع', '${fmtN(est)} ${_objective == 'clicks' ? 'ضغطة' : 'مشاهدة'}'),
        if (_bonus > 0) _kv('الهدية', '+$_bonus%'),
        _kv('المدة', '$_days أيام'),
        if (_link.text.trim().isNotEmpty) _kv('الزر', _label.text.isEmpty ? 'اعرف المزيد' : _label.text),
        const Divider(height: 22),
        _kv('المبلغ', fmtIqd(_budget), bold: true),
      ])),
      const SizedBox(height: 12),
      Text('• يراجع فريقنا الفيديو والدفع ثم يبدأ الظهور لكل المستخدمين.\n'
          '• يظهر الفيديو بعلامة «ممول» بين الفيديوهات.\n'
          '• مشاهداتك أنت لا تُحتسب، وكل جهاز يُحتسب 3 مرات يومياً كحد أقصى — أرقام حقيقية فقط.\n'
          '• المحتوى المخالف للإرشادات يُرفض ويُعاد المبلغ.',
          style: E.t(13, c: E.ink2, h: 1.7)),
    ];
  }

  Widget _choice(String t, String sub, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: on ? E.ink : Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? E.ink : E.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: E.t(15, w: FontWeight.w800, c: on ? Colors.white : E.ink)),
            const SizedBox(height: 4),
            Text(sub, style: E.t(12, c: on ? Colors.white70 : E.ink3)),
          ]),
        ),
      );
}

Widget _blackPill(String label, VoidCallback? onTap, {bool busy = false, bool white = false}) => Material(
      color: white ? E.card : E.ink,
      shape: StadiumBorder(side: white ? BorderSide(color: E.line) : BorderSide.none),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          height: 52,
          child: Center(child: busy
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: white ? E.ink : Colors.white))
              : Text(label, style: E.t(15.5, w: FontWeight.w800, c: white ? E.ink : Colors.white))),
        ),
      ),
    );

/// الدفع بأسلوب بنكي: بطاقة المبلغ والرمز · طرق التحويل مع النسخ · صورة الوصل · تأكيد
class PromotePayPage extends StatefulWidget {
  final Promo promo;
  final PromoRates rates;
  const PromotePayPage({super.key, required this.promo, required this.rates});
  @override
  State<PromotePayPage> createState() => _PromotePayPageState();
}

class _PromotePayPageState extends State<PromotePayPage> {
  int _method = 0;
  io.File? _receipt;
  final _txn = TextEditingController();
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    _txn.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (x != null) setState(() => _receipt = io.File(x.path));
  }

  Future<void> _confirm() async {
    final methods = widget.rates.methods;
    if (_receipt == null) { setState(() => _err = 'أرفق صورة وصل التحويل'); return; }
    setState(() { _busy = true; _err = ''; });
    try {
      await PromoApi.pay(widget.promo, method: methods.isEmpty ? 'تحويل' : methods[_method].s('name'), receipt: _receipt!, txn: _txn.text.trim());
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: E.card,
        title: Text('وصلنا طلبك ✓', style: E.t(17, w: FontWeight.w800)),
        content: Text('رقم الطلب ${widget.promo.code}\nسنراجع الدفع والفيديو ويبدأ الترويج فور الموافقة — يصلك إشعار.', style: E.t(14, c: E.ink2, h: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ));
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MyPromosPage()));
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.promo;
    final methods = widget.rates.methods;
    return Scaffold(
      backgroundColor: E.page,
      appBar: AppBar(backgroundColor: E.page, title: const Text('الدفع')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: E.ink, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('المبلغ المطلوب', style: E.t(13, c: Colors.white60)),
            const SizedBox(height: 4),
            Text(fmtIqd(p.budget), style: E.t(32, w: FontWeight.w800, c: Colors.white)),
            const SizedBox(height: 16),
            Row(children: [
              Text('رقم الطلب', style: E.t(13, c: Colors.white60)),
              const Spacer(),
              GestureDetector(
                onTap: () { Clipboard.setData(ClipboardData(text: p.code)); toast(context, 'نُسخ الرقم'); },
                child: Row(children: [
                  Text(p.code, textDirection: TextDirection.ltr, style: E.t(15, w: FontWeight.w800, c: Colors.white)),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 16, color: Colors.white60),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Text('اكتب رقم الطلب في ملاحظة التحويل إن أمكن', style: E.t(12, c: Colors.white54)),
          ]),
        ),
        const SizedBox(height: 18),
        Text('حوّل إلى', style: E.t(16, w: FontWeight.w800)),
        const SizedBox(height: 8),
        if (methods.isEmpty)
          _Box(child: Text('طرق الدفع لم تُضبط بعد — تواصل مع الدعم: ${Cfg.supportEmail}', style: E.t(13.5, c: E.ink2)))
        else
          for (int i = 0; i < methods.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => setState(() => _method = i),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: E.card, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _method == i ? E.ink : E.line, width: _method == i ? 1.6 : 1)),
                  child: Row(children: [
                    Icon(_method == i ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: E.ink),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(methods[i].s('name'), style: E.t(15, w: FontWeight.w800)),
                      Text(methods[i].s('account'), textDirection: TextDirection.ltr, style: E.t(14, c: E.ink2)),
                      if (methods[i].s('holder').isNotEmpty) Text(methods[i].s('holder'), style: E.t(12.5, c: E.ink3)),
                    ])),
                    IconButton(icon: const Icon(Icons.copy_rounded, size: 20), onPressed: () {
                      Clipboard.setData(ClipboardData(text: methods[i].s('account')));
                      toast(context, 'نُسخ');
                    }),
                  ]),
                ),
              ),
            ),
        const SizedBox(height: 12),
        Text('صورة الوصل', style: E.t(16, w: FontWeight.w800)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pick,
          child: Container(
            height: _receipt == null ? 110 : 220,
            decoration: BoxDecoration(color: E.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: E.line)),
            clipBehavior: Clip.antiAlias,
            child: _receipt == null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 32, color: E.ink2),
                    const SizedBox(height: 6),
                    Text('اضغط لإرفاق لقطة شاشة التحويل', style: E.t(13.5, c: E.ink2)),
                  ])
                : Image.file(_receipt!, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _txn, decoration: InputDecoration(hintText: 'رقم العملية (اختياري)', fillColor: E.card)),
        if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err, style: E.t(13, c: E.accent))),
        const SizedBox(height: 18),
        _blackPill('تأكيد الدفع', _busy ? null : _confirm, busy: _busy),
        const SizedBox(height: 8),
        _blackPill('ادفع لاحقاً', () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MyPromosPage())), white: true),
      ]),
    );
  }
}

/// ترويجاتي
class MyPromosPage extends StatefulWidget {
  const MyPromosPage({super.key});
  @override
  State<MyPromosPage> createState() => _MyPromosPageState();
}

class _MyPromosPageState extends State<MyPromosPage> {
  List<Promo>? _l;
  Map<String, String> _posters = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await PromoApi.mine();
      final ids = l.map((p) => p.videoId).where((x) => x.isNotEmpty).toSet().toList();
      if (ids.isNotEmpty) {
        final r = await sb.from('videos').select('id, poster').inFilter('id', ids);
        _posters = {for (final m in r) m['id'].toString(): (m['poster'] ?? '').toString()};
      }
      _l = l;
    } catch (_) {
      _l = [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: E.page,
        appBar: AppBar(backgroundColor: E.page, title: const Text('ترويجاتي')),
        body: _l == null
            ? const Loading()
            : _l!.isEmpty
                ? const EmptyState(icon: Icons.local_fire_department_outlined, title: 'لا ترويجات بعد',
                    sub: 'افتح أي فيديو لك واضغط «روّج» ليصل لآلاف المشاهدين')
                : RefreshIndicator(
                    color: E.accent,
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _l!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final p = _l![i];
                        final poster = _posters[p.videoId] ?? '';
                        return GestureDetector(
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PromoDetailPage(id: p.id)));
                            _load();
                          },
                          child: _Box(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 50, height: 66,
                                  child: poster.isEmpty ? ColoredBox(color: E.soft) : CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(p.code, textDirection: TextDirection.ltr, style: E.t(13, w: FontWeight.w700, c: E.ink3)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: p.statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                                    child: Text(p.statusLabel, style: E.t(12, w: FontWeight.w700, c: p.statusColor)),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                Text('${fmtN(p.done)} / ${fmtN(p.goal)} ${p.clicksGoal ? 'ضغطة' : 'مشاهدة'} · ${fmtIqd(p.budget)}',
                                    style: E.t(14, w: FontWeight.w700)),
                                const SizedBox(height: 6),
                                ClipRRect(borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(value: p.progress, minHeight: 5, color: E.ink, backgroundColor: E.soft)),
                              ])),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
      );
}

/// تفاصيل الترويج: الأرقام الدقيقة + الأيام + الوصل الرسمي + الإجراءات
class PromoDetailPage extends StatefulWidget {
  final int id;
  const PromoDetailPage({super.key, required this.id});
  @override
  State<PromoDetailPage> createState() => _PromoDetailPageState();
}

class _PromoDetailPageState extends State<PromoDetailPage> {
  Promo? _p;
  List<Map<String, dynamic>> _days = [];
  PromoRates? _rates;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([PromoApi.get(widget.id), PromoApi.daily(widget.id), PromoApi.rates()]);
      _p = r[0] as Promo?;
      _days = r[1] as List<Map<String, dynamic>>;
      _rates = r[2] as PromoRates;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _act(Future<void> Function() f) async {
    try { await f(); await _load(); } catch (e) { if (mounted) toast(context, errText(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: E.page,
      appBar: AppBar(backgroundColor: E.page, title: Text(p?.code ?? 'الترويج')),
      body: p == null
          ? const Loading()
          : RefreshIndicator(
              color: E.accent,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(p.statusLabel, style: E.t(17, w: FontWeight.w800, c: p.statusColor)),
                    const Spacer(),
                    Text('${(p.progress * 100).round()}%', style: E.t(17, w: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: p.progress, minHeight: 8, color: E.ink, backgroundColor: E.soft)),
                  const SizedBox(height: 8),
                  Text('${fmtN(p.done)} من ${fmtN(p.goal)} ${p.clicksGoal ? 'ضغطة مدفوعة' : 'مشاهدة مدفوعة'}', style: E.t(13.5, c: E.ink2)),
                  if (p.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('ملاحظة: ${p.reason}', style: E.t(13, c: E.accent))),
                ])),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.25,
                  children: [
                    _stat(fmtN(p.impressions), 'ظهور'),
                    _stat(fmtN(p.views), 'مشاهدة'),
                    _stat(fmtN(p.uniq), 'مشاهد فريد'),
                    _stat('${p.completeRate.toStringAsFixed(0)}%', 'أكمل المشاهدة'),
                    _stat('${p.avgWatch.toStringAsFixed(1)} ث', 'متوسط المشاهدة'),
                    _stat(fmtN(p.clicks), 'ضغطة على الزر'),
                  ],
                ),
                if (_days.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('المشاهدات يومياً', style: E.t(15, w: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _Box(child: _Bars(days: _days)),
                ],
                const SizedBox(height: 16),
                Text('الوصل الرسمي', style: E.t(15, w: FontWeight.w800)),
                const SizedBox(height: 8),
                _Box(child: Column(children: [
                  Row(children: [
                    Text(Cfg.appName, style: E.t(20, w: FontWeight.w900)),
                    const Spacer(),
                    Text(p.code, textDirection: TextDirection.ltr, style: E.t(14, w: FontWeight.w800)),
                  ]),
                  const Divider(height: 20),
                  _kv('الخدمة', 'ترويج فيديو — ${p.clicksGoal ? 'ضغطات' : 'مشاهدات'}'),
                  _kv('الهدف', '${fmtN(p.goal)}${p.bonusPct > 0 ? ' (شامل هدية ${p.bonusPct}%)' : ''}'),
                  _kv('المدة', '${p.days} أيام'),
                  _kv('تاريخ الطلب', p.created == null ? '-' : '${p.created!.day}/${p.created!.month}/${p.created!.year}'),
                  _kv('طريقة الدفع', p.payStatus == 'free' ? 'هدية' : (p.payMethod.isEmpty ? '-' : p.payMethod)),
                  _kv('حالة الدفع', const {'unpaid': 'غير مدفوع', 'submitted': 'قيد التحقق', 'paid': 'مدفوع ✓', 'free': 'مجاني'}[p.payStatus] ?? p.payStatus),
                  const Divider(height: 20),
                  _kv('المبلغ', fmtIqd(p.budget), bold: true),
                ])),
                const SizedBox(height: 16),
                if (p.needsPay && _rates != null)
                  _blackPill('ادفع الآن', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PromotePayPage(promo: p, rates: _rates!)))),
                if (p.status == 'active') _blackPill('إيقاف مؤقت', () => _act(() => PromoApi.pause(p.id, true)), white: true),
                if (p.status == 'paused') _blackPill('استئناف', () => _act(() => PromoApi.pause(p.id, false))),
                if (p.status == 'pending') ...[
                  const SizedBox(height: 8),
                  _blackPill('إلغاء الطلب', () async {
                    if (await confirm(context, 'إلغاء الطلب؟', p.payStatus == 'submitted' ? 'إن كنت دفعت تواصل مع الدعم لاسترداد المبلغ.' : '',
                        ok: 'إلغاء الطلب', danger: true)) {
                      _act(() => PromoApi.cancel(p.id));
                    }
                  }, white: true),
                ],
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Share.share('وصل ${Cfg.appName}\n${p.code}\nترويج فيديو · ${fmtIqd(p.budget)}\nالحالة: ${p.statusLabel}'),
                  icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('مشاركة الوصل'),
                ),
              ]),
            ),
    );
  }

  Widget _stat(String n, String l) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: E.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: E.line)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(n, style: E.t(18, w: FontWeight.w800)),
          Text(l, textAlign: TextAlign.center, style: E.t(11.5, c: E.ink3)),
        ]),
      );
}

/// أعمدة يومية بسيطة
class _Bars extends StatelessWidget {
  final List<Map<String, dynamic>> days;
  const _Bars({required this.days});
  @override
  Widget build(BuildContext context) {
    final last = days.length > 14 ? days.sublist(days.length - 14) : days;
    final mx = last.fold<int>(1, (a, d) => math.max(a, d.i('views')));
    return SizedBox(
      height: 130,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in last)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(fmtN(d.i('views')), style: E.t(9.5, c: E.ink3)),
              const SizedBox(height: 2),
              Container(height: 90 * d.i('views') / mx + 2,
                  decoration: BoxDecoration(color: E.ink, borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 4),
              Text(d.s('day').length >= 10 ? d.s('day').substring(8, 10) : '', style: E.t(9.5, c: E.ink3)),
            ]),
          )),
      ]),
    );
  }
}
