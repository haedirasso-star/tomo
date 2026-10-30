part of '../main.dart';

class Avatar extends StatelessWidget {
  final String url, name;
  final double size;
  final bool ring;
  const Avatar(this.url, {super.key, this.name = '', this.size = 44, this.ring = false});

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final fallback = Container(
      color: E.soft,
      alignment: Alignment.center,
      child: Text(letter, style: E.t(size * 0.4, w: FontWeight.w700, c: E.ink2)),
    );
    final img = ClipOval(
      child: SizedBox(
        width: size, height: size,
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, memCacheWidth: (size * 3).round(),
                placeholder: (_, __) => fallback, errorWidget: (_, __, ___) => fallback),
      ),
    );
    if (!ring) return img;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
      child: img,
    );
  }
}

class Verified extends StatelessWidget {
  final double size;
  const Verified({super.key, this.size = 15});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Icon(Icons.verified_rounded, size: size, color: E.online),
      );
}

/// زر بأسلوب الكبسولة (أساسي ملوّن / ثانوي رمادي)
class Pill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary, busy;
  final IconData? icon;
  final double height;
  final EdgeInsets padding;
  const Pill(this.label, {super.key, this.onTap, this.primary = false, this.busy = false, this.icon, this.height = 44,
      this.padding = const EdgeInsets.symmetric(horizontal: 18)});

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : E.ink;
    return Material(
      color: primary ? E.accent : E.soft,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: busy ? null : onTap,
        child: Container(
          height: height,
          padding: padding,
          alignment: Alignment.center,
          child: busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: E.t(15, w: FontWeight.w700, c: fg))),
                ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final Widget? action;
  final bool dark;
  const EmptyState({super.key, required this.icon, required this.title, this.sub = '', this.action, this.dark = false});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: dark ? Colors.white38 : E.ink3),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: E.t(17, w: FontWeight.w700, c: dark ? Colors.white : E.ink)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(sub, textAlign: TextAlign.center, style: E.t(14, c: dark ? Colors.white60 : E.ink3)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

class Loading extends StatelessWidget {
  final bool dark;
  const Loading({super.key, this.dark = false});
  @override
  Widget build(BuildContext context) => Center(
      child: SizedBox(width: 26, height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: dark ? Colors.white : E.accent)));
}

/// شبكة الفيديوهات (الملف الشخصي · المحفوظات · الإعجابات)
class VideoGrid extends StatelessWidget {
  final List<Video> items;
  final void Function(int index) onOpen;
  final bool showViews;
  const VideoGrid({super.key, required this.items, required this.onOpen, this.showViews = true});

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 3 / 4, mainAxisSpacing: 1.5, crossAxisSpacing: 1.5),
        itemBuilder: (_, i) {
          final v = items[i];
          return GestureDetector(
            onTap: () => onOpen(i),
            child: Stack(fit: StackFit.expand, children: [
              Container(color: const Color(0xFF1E1E22)),
              if (v.poster.isNotEmpty)
                CachedNetworkImage(imageUrl: v.poster, fit: BoxFit.cover, memCacheWidth: 360,
                    errorWidget: (_, __, ___) => const SizedBox()),
              if (v.status == 'processing')
                Container(color: Colors.black45, alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('يُجهَّز…', style: E.t(12, w: FontWeight.w700, c: Colors.white)),
                    ])),
              if (v.privacy != 'public')
                const PositionedDirectional(top: 6, end: 6, child: Icon(Icons.lock_rounded, color: Colors.white, size: 16)),
              if (showViews)
                PositionedDirectional(
                  bottom: 6, start: 6,
                  child: Row(children: [
                    const Icon(Icons.play_arrow_outlined, color: Colors.white, size: 18),
                    Text(fmtN(v.views), style: E.t(13, w: FontWeight.w700, c: Colors.white).copyWith(
                        shadows: const [Shadow(blurRadius: 4, color: Colors.black54)])),
                  ]),
                ),
            ]),
          );
        },
      );
}

/// ورقة سفلية بقائمة خيارات
Future<T?> sheetMenu<T>(BuildContext context, List<(IconData, String, T, bool)> items) => showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      backgroundColor: E.card,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final it in items)
            ListTile(
              leading: Icon(it.$1, color: it.$4 ? E.accent : E.ink),
              title: Text(it.$2, style: E.t(15, w: FontWeight.w600, c: it.$4 ? E.accent : E.ink)),
              onTap: () => Navigator.pop(ctx, it.$3),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: E.card,
      title: Text(title, style: E.t(17, w: FontWeight.w700)),
      content: Text(body, style: E.t(14, c: E.ink2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: E.t(14, c: E.ink2))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok, style: E.t(14, w: FontWeight.w700, c: danger ? E.accent : E.ink))),
      ],
    ),
  );
  return r == true;
}

/// الإبلاغ عن محتوى (مطلوب في المتاجر)
Future<void> reportFlow(BuildContext context, String kind, String target) async {
  if (!await Me.ensure(context) || !context.mounted) return;
  const reasons = ['محتوى جنسي أو عُري', 'عنف أو إيذاء', 'تحرّش أو تنمّر', 'خطاب كراهية', 'احتيال أو بريد مزعج', 'انتهاك حقوق ملكية', 'إيذاء قاصرين', 'شيء آخر'];
  final reason = await sheetMenu<String>(context, [for (final r in reasons) (Icons.flag_outlined, r, r, false)]);
  if (reason == null || !context.mounted) return;
  try {
    await Api.report(kind, target, reason);
    if (context.mounted) toast(context, 'شكراً — وصلنا البلاغ وسنراجعه خلال 24 ساعة');
  } catch (e) {
    if (context.mounted) toast(context, errText(e));
  }
}
