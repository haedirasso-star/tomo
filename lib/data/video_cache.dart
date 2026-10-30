part of '../main.dart';

/// كاش الفيديوهات على الجهاز: الفيديو التالي يُنزَّل كاملاً قبل الوصول إليه ⇐ يبدأ فوراً بلا تقطيع
class VideoCache {
  VideoCache._();
  static final fcm.CacheManager _m = fcm.CacheManager(fcm.Config(
    'tomo_videos_v1',
    stalePeriod: const Duration(days: 5),
    maxNrOfCacheObjects: 250,
  ));
  static final Map<String, Future<io.File?>> _inflight = {};

  static Future<io.File?> cached(String url) async {
    try {
      final f = await _m.getFileFromCache(url);
      return f?.file;
    } catch (_) {
      return null;
    }
  }

  static Future<io.File?> fetch(String url) {
    if (url.isEmpty) return Future.value(null);
    return _inflight[url] ??= () async {
      try {
        final f = await _m.getSingleFile(url);
        return f;
      } catch (_) {
        return null;
      } finally {
        unawaited(Future<void>.delayed(const Duration(seconds: 1), () => _inflight.remove(url)));
      }
    }();
  }

  static Future<void> clear() => _m.emptyCache();
}
