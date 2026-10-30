part of '../main.dart';

/// فتح فيديو من شبكة (ملف شخصي · محفوظات · إشعار) بنفس مشغّل الرئيسية مع التمرير بين البقية
class VideoListPage extends StatelessWidget {
  final List<Video> items;
  final int start;
  const VideoListPage({super.key, required this.items, required this.start});

  static Future<void> open(BuildContext context, List<Video> items, int start) => Navigator.of(context).push(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => VideoListPage(items: items, start: start),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      ));

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: VideoPager(source: FeedSource.fixed(items), start: start, showBack: true),
        ),
      );
}
