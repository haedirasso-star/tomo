part of '../main.dart';

/// 1234 ⇐ 1.2K · 1500000 ⇐ 1.5M (أرقام إنجليزية مثل التطبيقات العالمية)
String fmtN(num v) {
  final n = v.round();
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}K';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

String ago(DateTime? d) {
  if (d == null) return '';
  final s = DateTime.now().difference(d);
  if (s.inSeconds < 60) return 'الآن';
  if (s.inMinutes < 60) return 'منذ ${s.inMinutes} د';
  if (s.inHours < 24) return 'منذ ${s.inHours} س';
  if (s.inDays < 7) return 'منذ ${s.inDays} ي';
  if (s.inDays < 365) return '${d.day}/${d.month}';
  return '${d.day}/${d.month}/${d.year}';
}

String errText(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'البريد أو كلمة المرور غير صحيحة';
    if (m.contains('already registered')) return 'هذا البريد مسجّل مسبقاً — سجّل الدخول';
    if (m.contains('password')) return 'كلمة المرور ضعيفة (6 أحرف على الأقل)';
    if (m.contains('email not confirmed')) return 'أكّد بريدك من الرسالة التي وصلتك أولاً';
    return e.message;
  }
  if (e is PostgrestException) {
    if (e.code == '23505') return 'اسم المستخدم محجوز — جرّب غيره';
    if (e.code == '23514') return 'القيمة غير صالحة';
    return e.message;
  }
  if (e is StorageException) return 'فشل الرفع: ${e.message}';
  if (e is io.SocketException || e is TimeoutException) return 'تحقق من الاتصال بالإنترنت';
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1800)));
}

extension MapX on Map<String, dynamic> {
  String s(String k) => (this[k] ?? '').toString();
  int i(String k) => this[k] is num ? (this[k] as num).toInt() : int.tryParse('${this[k] ?? ''}') ?? 0;
  bool b(String k) => this[k] == true;
  DateTime? d(String k) => this[k] == null ? null : DateTime.tryParse('${this[k]}')?.toLocal();
}
