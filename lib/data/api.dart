part of '../main.dart';

SupabaseClient get sb => Supabase.instance.client;
String? get myId => sb.auth.currentUser?.id;

/// كل التعامل مع الخادم في مكان واحد
class Api {
  Api._();

  // ── الفيديوهات ─────────────────────────────────────────────────────
  /// استدعاء دالة api في الخادم (الرفع · الحذف · حذف الحساب) مع رسالة خطأ عربية واضحة
  static Future<Map<String, dynamic>> fn(String action, [Map<String, dynamic> body = const {}]) async {
    try {
      final r = await sb.functions.invoke('api', body: {'action': action, ...body});
      return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? '${d['error']}' : 'تعذّر الاتصال بالخادم (${e.status})');
    }
  }

  static Future<dynamic> _soft(Future<dynamic> f) async {
    try { return await f; } catch (_) { return const []; }
  }

  /// «لك»: فيديوهات الخوارزمية + فيديو ممول واحد في الموضع الخامس (إن وُجدت حملة فعّالة)
  static Future<List<Video>> forYou({List<String> seen = const [], int limit = 10}) async {
    final ids = seen.take(300).toList();
    final res = await Future.wait([
      sb.rpc('feed_for_you', params: {'p_limit': limit, 'p_seen': ids}),
      _soft(sb.rpc('promo_pick', params: {'p_seen': ids, 'p_limit': 1})),
    ]);
    final l = [for (final m in (res[0] as List)) Video.of(Map<String, dynamic>.from(m as Map))];
    final promos = [for (final m in (res[1] as List? ?? const [])) Video.of(Map<String, dynamic>.from(m as Map))];
    for (final p in promos) {
      l.removeWhere((v) => v.id == p.id);
      l.insert(math.min(4, l.length), p);
    }
    return _withMine(l);
  }

  static Future<List<Video>> following({DateTime? before, int limit = 10}) async {
    if (myId == null) return [];
    final r = await sb.rpc('feed_following', params: {
      'p_limit': limit,
      'p_before': (before ?? DateTime.now().add(const Duration(minutes: 1))).toUtc().toIso8601String(),
    });
    return _withMine([for (final m in (r as List)) Video.of(Map<String, dynamic>.from(m as Map))]);
  }

  static Future<List<Video>> ofUser(String uid, {int offset = 0, int limit = 30}) async {
    final r = await sb.from('feed_items').select().eq('user_id', uid).order('created_at', ascending: false).range(offset, offset + limit - 1);
    return _withMine([for (final m in r) Video.of(m)]);
  }

  static Future<List<Video>> liked() async {
    if (myId == null) return [];
    final r = await sb.from('likes').select('videos(*, profiles(username, name, avatar, verified))').eq('user_id', myId!).order('created_at', ascending: false).limit(60);
    return _withMine([for (final m in r) if (m['videos'] is Map) Video.of(Map<String, dynamic>.from(m['videos'] as Map))]);
  }

  static Future<List<Video>> saved() async {
    if (myId == null) return [];
    final r = await sb.from('saves').select('videos(*, profiles(username, name, avatar, verified))').eq('user_id', myId!).order('created_at', ascending: false).limit(60);
    return _withMine([for (final m in r) if (m['videos'] is Map) Video.of(Map<String, dynamic>.from(m['videos'] as Map))]);
  }

  /// يملأ «أعجبني / حفظته» للمستخدم الحالي دفعة واحدة
  static Future<List<Video>> _withMine(List<Video> l) async {
    final me = myId;
    if (me == null || l.isEmpty) return l;
    final ids = l.map((v) => v.id).toList();
    try {
      final res = await Future.wait([
        sb.from('likes').select('video_id').eq('user_id', me).inFilter('video_id', ids),
        sb.from('saves').select('video_id').eq('user_id', me).inFilter('video_id', ids),
      ]);
      final lk = {for (final m in res[0]) m['video_id'].toString()};
      final sv = {for (final m in res[1]) m['video_id'].toString()};
      for (final v in l) { v.liked = lk.contains(v.id); v.saved = sv.contains(v.id); }
    } catch (_) {}
    return l;
  }

  static Future<void> like(Video v, bool on) async {
    final me = myId!;
    if (on) {
      await sb.from('likes').upsert({'user_id': me, 'video_id': v.id}, ignoreDuplicates: true);
    } else {
      await sb.from('likes').delete().eq('user_id', me).eq('video_id', v.id);
    }
  }

  static Future<void> save(Video v, bool on) async {
    final me = myId!;
    if (on) {
      await sb.from('saves').upsert({'user_id': me, 'video_id': v.id}, ignoreDuplicates: true);
    } else {
      await sb.from('saves').delete().eq('user_id', me).eq('video_id', v.id);
    }
  }

  static Future<void> deleteVideo(Video v) => fn('video_delete', {'id': v.id});

  static Future<void> setPrivacy(Video v, String privacy) => sb.from('videos').update({'privacy': privacy}).eq('id', v.id);

  /// النشر: روابط رفع موقّعة من الخادم ⇐ رفع مباشر إلى R2 مع نسبة التقدّم ⇐ الخادم يتحقق وينشئ الفيديو
  /// (والضغط إلى 720p يتم تلقائياً على الخادم إن كان مفعّلاً)
  static Future<bool> publish({
    required io.File file, io.File? poster, required String caption, required String privacy,
    required bool allowComments, required int duration, required int width, required int height,
    void Function(double progress)? onProgress,
  }) async {
    var ext = file.path.split('.').last.toLowerCase();
    if (ext.length > 4 || ext.isEmpty) ext = 'mp4';
    final size = await file.length();
    final init = await fn('media_init', {'ext': ext, 'size': size});
    final id = init.s('id');
    final v = Map<String, dynamic>.from(init['video'] as Map);
    await _put(v.s('url'), file, v.s('type'), (p) => onProgress?.call(p * 0.96));
    var hasPoster = false;
    if (poster != null) {
      try {
        final pp = Map<String, dynamic>.from(init['poster'] as Map);
        await _put(pp.s('url'), poster, 'image/jpeg', null);
        hasPoster = true;
      } catch (_) {}
    }
    onProgress?.call(0.98);
    final r = await fn('media_publish', {
      'id': id, 'ext': init.s('ext'), 'caption': caption, 'privacy': privacy, 'allow_comments': allowComments,
      'duration': duration, 'width': width, 'height': height, 'poster': hasPoster,
    });
    onProgress?.call(1);
    return r['processing'] == true;
  }

  static Future<void> _put(String url, io.File f, String type, void Function(double)? onP) async {
    final len = await f.length();
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.putUrl(Uri.parse(url));
      req.headers.set(io.HttpHeaders.contentTypeHeader, type);
      req.contentLength = len;
      var sent = 0;
      await req.addStream(f.openRead().map((chunk) {
        sent += chunk.length;
        onP?.call(len == 0 ? 1 : sent / len);
        return chunk;
      }));
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode >= 300) throw Exception('فشل الرفع (${res.statusCode}) — تحقق من الإنترنت وأعد المحاولة');
    } finally {
      client.close(force: true);
    }
  }

  // ── التعليقات ──────────────────────────────────────────────────────
  static Future<List<Comment>> comments(String videoId) async {
    final r = await sb.from('comments').select('*, profiles(username, avatar)').eq('video_id', videoId).order('created_at', ascending: false).limit(200);
    return [for (final m in r) Comment.of(m)];
  }

  static Future<Comment> addComment(String videoId, String body) async {
    final r = await sb.from('comments').insert({'video_id': videoId, 'user_id': myId!, 'body': body}).select('*, profiles(username, avatar)').single();
    return Comment.of(r);
  }

  static Future<void> deleteComment(int id) => sb.from('comments').delete().eq('id', id);

  // ── الحسابات والمتابعة ──────────────────────────────────────────────
  static Future<Profile?> profile(String id) async {
    final r = await sb.from('profiles').select().eq('id', id).maybeSingle();
    return r == null ? null : Profile.of(r);
  }

  static Future<Profile?> byUsername(String u) async {
    final r = await sb.from('profiles').select().eq('username', u.toLowerCase()).maybeSingle();
    return r == null ? null : Profile.of(r);
  }

  static Future<bool> isFollowing(String uid) async {
    if (myId == null) return false;
    final r = await sb.from('follows').select('followee').eq('follower', myId!).eq('followee', uid).maybeSingle();
    return r != null;
  }

  static Future<Set<String>> followingIds(List<String> ids) async {
    if (myId == null || ids.isEmpty) return {};
    final r = await sb.from('follows').select('followee').eq('follower', myId!).inFilter('followee', ids);
    return {for (final m in r) m['followee'].toString()};
  }

  static Future<void> follow(String uid, bool on) async {
    if (on) {
      await sb.from('follows').upsert({'follower': myId!, 'followee': uid}, ignoreDuplicates: true);
    } else {
      await sb.from('follows').delete().eq('follower', myId!).eq('followee', uid);
    }
  }

  /// قائمة المتابِعين أو المتابَعين لحساب
  static Future<List<Profile>> people(String uid, {required bool followers}) async {
    final r = followers
        ? await sb.from('follows').select('profiles!follows_follower_fkey(*)').eq('followee', uid).order('created_at', ascending: false).limit(200)
        : await sb.from('follows').select('profiles!follows_followee_fkey(*)').eq('follower', uid).order('created_at', ascending: false).limit(200);
    return [for (final m in r) if (m['profiles'] is Map) Profile.of(Map<String, dynamic>.from(m['profiles'] as Map))];
  }

  /// الأصدقاء = متابعة متبادلة
  static Future<List<Profile>> friends() async {
    final me = myId;
    if (me == null) return [];
    final mine = await people(me, followers: false);
    if (mine.isEmpty) return [];
    final back = await sb.from('follows').select('follower').eq('followee', me).inFilter('follower', mine.map((p) => p.id).toList());
    final ids = {for (final m in back) m['follower'].toString()};
    return mine.where((p) => ids.contains(p.id)).toList();
  }

  static Future<List<Profile>> suggested() async {
    final r = await sb.rpc('suggested_users', params: {'p_limit': 30});
    return [for (final m in (r as List)) Profile.of(Map<String, dynamic>.from(m as Map))];
  }

  static Future<List<Profile>> search(String q) async {
    final r = await sb.rpc('search_users', params: {'p_q': q, 'p_limit': 30});
    return [for (final m in (r as List)) Profile.of(Map<String, dynamic>.from(m as Map))];
  }

  static Future<void> updateProfile(Map<String, dynamic> v) => sb.from('profiles').update(v).eq('id', myId!);

  static Future<String> uploadAvatar(io.File f) async {
    final path = '${myId!}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final store = sb.storage.from('avatars');
    await store.upload(path, f, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
    return store.getPublicUrl(path);
  }

  // ── الحظر والإبلاغ ─────────────────────────────────────────────────
  static Future<void> block(String uid) async {
    await sb.from('blocks').upsert({'blocker': myId!, 'blocked': uid}, ignoreDuplicates: true);
    try { await follow(uid, false); } catch (_) {}
  }

  static Future<void> unblock(String uid) => sb.from('blocks').delete().eq('blocker', myId!).eq('blocked', uid);

  static Future<void> report(String kind, String target, String reason) =>
      sb.from('reports').insert({'reporter': myId!, 'kind': kind, 'target': target, 'reason': reason});

  // ── المحادثات ──────────────────────────────────────────────────────
  static Future<List<Conv>> convs() async {
    final me = myId;
    if (me == null) return [];
    final r = await sb.from('conversations').select().order('last_at', ascending: false).limit(100);
    final ids = {for (final m in r) ...[m['a'].toString(), m['b'].toString()]}..remove(me);
    final people = <String, Profile>{};
    if (ids.isNotEmpty) {
      final ps = await sb.from('profiles').select().inFilter('id', ids.toList());
      for (final m in ps) { final p = Profile.of(m); people[p.id] = p; }
    }
    return [for (final m in r) Conv.of(m, me, people)];
  }

  static Future<String> openConv(String other) async => (await sb.rpc('open_conv', params: {'p_other': other})).toString();

  static Future<List<Msg>> messages(String conv, {int? beforeId}) async {
    var q = sb.from('messages').select().eq('conv_id', conv);
    if (beforeId != null) q = q.lt('id', beforeId);
    final r = await q.order('id', ascending: false).limit(50);
    return [for (final m in r) Msg.of(m)];
  }

  static Future<Msg> send(String conv, String body, {int? replyTo, String? videoId}) async {
    final r = await sb.from('messages').insert({
      'conv_id': conv, 'sender': myId!, 'body': body,
      if (replyTo != null) 'reply_to': replyTo,
      if (videoId != null) 'video_id': videoId,
    }).select().single();
    return Msg.of(r);
  }

  static Future<void> unsend(int id) => sb.from('messages').update({'deleted': true}).eq('id', id);
  static Future<void> readConv(String conv) => sb.rpc('read_conv', params: {'p_conv': conv});

  // ── الإشعارات ──────────────────────────────────────────────────────
  static Future<List<Notif>> notifs() async {
    if (myId == null) return [];
    final r = await sb.from('notifications').select('*, profiles!notifications_actor_fkey(*)').eq('user_id', myId!).order('id', ascending: false).limit(100);
    return [for (final m in r) Notif.of(m)];
  }

  static Future<void> readNotifs() async {
    if (myId == null) return;
    await sb.from('notifications').update({'read': true}).eq('user_id', myId!).eq('read', false);
  }

  static Future<int> unreadNotifs() async {
    if (myId == null) return 0;
    final r = await sb.from('notifications').select('id').eq('user_id', myId!).eq('read', false).limit(100);
    return r.length;
  }

  static Future<Video?> video(String id) async {
    final r = await sb.from('feed_items').select().eq('id', id).maybeSingle();
    if (r == null) return null;
    return (await _withMine([Video.of(r)])).first;
  }

  // ── الحساب ─────────────────────────────────────────────────────────
  /// حذف الحساب نهائياً: الخادم يحذف كل الملفات من R2 والتخزين ثم الحساب وكل بياناته
  static Future<void> deleteAccount() async {
    await fn('account_delete');
    await sb.auth.signOut();
  }
}
