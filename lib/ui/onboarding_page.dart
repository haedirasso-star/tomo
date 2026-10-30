part of '../main.dart';

/// إكمال الحساب لمن دخل بغوغل/فيسبوك/آبل: اسم المستخدم · الاسم · سنة الميلاد (13+) · الموافقة على الشروط
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final _user = TextEditingController(text: Me.profile?.username ?? '');
  late final _name = TextEditingController(text: Me.profile?.name ?? '');
  int? _year;
  bool _agree = false, _busy = false;
  String _err = '';

  @override
  void dispose() {
    _user.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final u = _user.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(u)) {
      setState(() => _err = 'اسم المستخدم: 3–24 حرفاً إنجليزياً صغيراً أو أرقاماً أو _ .');
      return;
    }
    if (_year == null) { setState(() => _err = 'اختر سنة ميلادك'); return; }
    if (DateTime.now().year - _year! < 13) {
      setState(() => _err = 'عذراً، يجب أن يكون عمرك 13 سنة أو أكثر لاستخدام ${Cfg.appName}');
      return;
    }
    if (!_agree) { setState(() => _err = 'وافق على الشروط وسياسة الخصوصية للمتابعة'); return; }
    setState(() { _busy = true; _err = ''; });
    try {
      await Api.updateProfile({'username': u, 'name': _name.text.trim(), 'birth_year': _year, 'onboarded': true});
      await Me.refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (int y = DateTime.now().year; y >= DateTime.now().year - 90; y--) y];
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('أكمل حسابك'),
          actions: [TextButton(onPressed: () async { await sb.auth.signOut(); if (context.mounted) Navigator.of(context).pop(); },
              child: Text('خروج', style: E.t(14, c: E.ink3)))],
        ),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('خطوة أخيرة', style: E.t(22, w: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('اختر اسماً يعرفك به الناس', style: E.t(14, c: E.ink3)),
          const SizedBox(height: 22),
          TextField(controller: _user, textDirection: TextDirection.ltr, autocorrect: false,
              decoration: const InputDecoration(hintText: 'اسم المستخدم (english)', prefixText: '@ ')),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: const InputDecoration(hintText: 'الاسم الظاهر')),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _year, hint: Text('سنة الميلاد', style: E.t(14, c: E.ink3)), menuMaxHeight: 320,
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) => setState(() => _year = v),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _agree, onChanged: (v) => setState(() => _agree = v == true),
            contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: E.accent,
            title: Wrap(children: [
              Text('أوافق على ', style: E.t(13, c: E.ink2)),
              GestureDetector(onTap: () => LegalPage.open(context, terms: true), child: Text('شروط الاستخدام', style: E.t(13, w: FontWeight.w700))),
              Text(' و', style: E.t(13, c: E.ink2)),
              GestureDetector(onTap: () => LegalPage.open(context), child: Text('سياسة الخصوصية', style: E.t(13, w: FontWeight.w700))),
            ]),
          ),
          if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err, style: E.t(13, c: E.accent))),
          const SizedBox(height: 16),
          Pill('متابعة', primary: true, busy: _busy, onTap: _save, height: 48),
        ]),
      ),
    );
  }
}
