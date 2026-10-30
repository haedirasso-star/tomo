part of '../../main.dart';

/// تعديل الملف الشخصي: الصورة · الاسم · اسم المستخدم · النبذة · الرابط
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final Profile? _p = Me.profile;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _user = TextEditingController(text: _p?.username ?? '');
  late final _bio = TextEditingController(text: _p?.bio ?? '');
  late final _link = TextEditingController(text: _p?.link ?? '');
  String _avatar = '';
  bool _busy = false, _uploading = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _avatar = _p?.avatar ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _user, _bio, _link]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
    if (x == null) return;
    setState(() => _uploading = true);
    try {
      _avatar = await Api.uploadAvatar(io.File(x.path));
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    final u = _user.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(u)) {
      setState(() => _err = 'اسم المستخدم: 3–24 حرفاً إنجليزياً صغيراً أو أرقاماً أو _ .');
      return;
    }
    setState(() { _busy = true; _err = ''; });
    try {
      await Api.updateProfile({
        'name': _name.text.trim(), 'username': u, 'bio': _bio.text.trim(), 'link': _link.text.trim(), 'avatar': _avatar,
      });
      await Me.refresh();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = errText(e); });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('تعديل الملف الشخصي'),
          actions: [
            TextButton(onPressed: _busy ? null : _save,
                child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('حفظ', style: E.t(15, w: FontWeight.w800, c: E.accent))),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: GestureDetector(
              onTap: _uploading ? null : _pickAvatar,
              child: Stack(alignment: Alignment.center, children: [
                Avatar(_avatar, name: _user.text, size: 100),
                Container(width: 100, height: 100, decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle)),
                _uploading ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 30),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text('تغيير الصورة', style: E.t(13.5, w: FontWeight.w600, c: E.ink2))),
          const SizedBox(height: 24),
          _field('الاسم', _name, max: 40),
          _field('اسم المستخدم', _user, max: 24, ltr: true, prefix: '@ '),
          _field('النبذة', _bio, max: 160, lines: 3),
          _field('الرابط', _link, max: 200, ltr: true, hint: 'example.com'),
          if (_err.isNotEmpty) Text(_err, style: E.t(13, c: E.accent)),
        ]),
      );

  Widget _field(String label, TextEditingController c, {int max = 40, bool ltr = false, int lines = 1, String? prefix, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: E.t(13, w: FontWeight.w600, c: E.ink3)),
          const SizedBox(height: 6),
          TextField(
            controller: c, maxLength: max, maxLines: lines, minLines: 1,
            textDirection: ltr ? TextDirection.ltr : null, autocorrect: !ltr,
            decoration: InputDecoration(prefixText: prefix, hintText: hint),
          ),
        ]),
      );
}
