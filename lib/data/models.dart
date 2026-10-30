part of '../main.dart';

class Profile {
  final String id, username, name, bio, link, avatar, dm, role;
  final int followers, following, likes, videos, birthYear;
  final bool private, verified, banned, onboarded;
  const Profile({
    required this.id, required this.username, this.name = '', this.bio = '', this.link = '', this.avatar = '',
    this.dm = 'friends', this.role = 'user', this.followers = 0, this.following = 0, this.likes = 0, this.videos = 0,
    this.birthYear = 0, this.private = false, this.verified = false, this.banned = false, this.onboarded = false,
  });
  String get display => name.isNotEmpty ? name : username;
  bool get staff => role == 'admin' || role == 'moderator';
  bool get admin => role == 'admin';

  factory Profile.of(Map<String, dynamic> m) => Profile(
        id: m.s('id'), username: m.s('username'), name: m.s('name'), bio: m.s('bio'), link: m.s('link'),
        avatar: m.s('avatar'), dm: m.s('dm').isEmpty ? 'friends' : m.s('dm'),
        role: m.s('role').isEmpty ? 'user' : m.s('role'),
        followers: m.i('followers'), following: m.i('following'), likes: m.i('likes'), videos: m.i('videos'),
        birthYear: m.i('birth_year'), private: m.b('private'), verified: m.b('verified'), banned: m.b('banned'),
        onboarded: m.b('onboarded'),
      );
}

class Video {
  final String id, userId, caption, url, path, poster, posterPath, privacy, status;
  /// رقم حملة الترويج إن ظهر الفيديو «ممولاً» (للعدّادات المدفوعة)
  final int cid;
  final String username, authorName, authorAvatar, ctaLabel, ctaLink;
  final bool authorVerified, allowComments, sponsored;
  final int duration, width, height;
  int views, likes, comments, shares, saves;
  bool liked, saved;
  final DateTime? created;

  Video({
    required this.id, required this.userId, required this.url, this.caption = '', this.path = '', this.poster = '',
    this.posterPath = '', this.privacy = 'public', this.status = 'ready', this.cid = 0, this.username = '', this.authorName = '', this.authorAvatar = '',
    this.ctaLabel = '', this.ctaLink = '', this.authorVerified = false, this.allowComments = true, this.sponsored = false,
    this.duration = 0, this.width = 0, this.height = 0, this.views = 0, this.likes = 0, this.comments = 0,
    this.shares = 0, this.saves = 0, this.liked = false, this.saved = false, this.created,
  });

  /// صف من feed_items (فيه بيانات صاحب الفيديو) أو من videos مع profiles(...)
  factory Video.of(Map<String, dynamic> m) {
    final p = m['profiles'] is Map ? Map<String, dynamic>.from(m['profiles'] as Map) : const <String, dynamic>{};
    return Video(
      id: m.s('id'), userId: m.s('user_id'), url: m.s('url'), caption: m.s('caption'), path: m.s('path'),
      poster: m.s('poster'), posterPath: m.s('poster_path'), privacy: m.s('privacy'),
      status: m.s('status').isEmpty ? 'ready' : m.s('status'), cid: m.i('cid'),
      username: m.s('username').isNotEmpty ? m.s('username') : p.s('username'),
      authorName: m.s('author_name').isNotEmpty ? m.s('author_name') : p.s('name'),
      authorAvatar: m.s('author_avatar').isNotEmpty ? m.s('author_avatar') : p.s('avatar'),
      authorVerified: m.b('author_verified') || p.b('verified'),
      allowComments: m['allow_comments'] != false, sponsored: m.b('sponsored') || m.i('cid') > 0,
      ctaLabel: m.s('promo_cta_label').isNotEmpty ? m.s('promo_cta_label') : m.s('cta_label'),
      ctaLink: m.s('promo_cta_link').isNotEmpty ? m.s('promo_cta_link') : m.s('cta_link'),
      duration: m.i('duration'), width: m.i('width'), height: m.i('height'),
      views: m.i('views'), likes: m.i('likes'), comments: m.i('comments'), shares: m.i('shares'), saves: m.i('saves'),
      created: m.d('created_at'),
    );
  }

  bool get landscape => width > 0 && height > 0 && width > height * 1.1;
}

class Comment {
  final int id;
  final String videoId, userId, body, username, avatar;
  final DateTime? created;
  const Comment({required this.id, required this.videoId, required this.userId, required this.body,
      this.username = '', this.avatar = '', this.created});
  factory Comment.of(Map<String, dynamic> m) {
    final p = m['profiles'] is Map ? Map<String, dynamic>.from(m['profiles'] as Map) : const <String, dynamic>{};
    return Comment(id: m.i('id'), videoId: m.s('video_id'), userId: m.s('user_id'), body: m.s('body'),
        username: p.s('username'), avatar: p.s('avatar'), created: m.d('created_at'));
  }
}

class Conv {
  final String id, otherId, lastBody, lastBy;
  final Profile? other;
  final int unread;
  final DateTime? lastAt, otherReadAt;
  const Conv({required this.id, required this.otherId, this.other, this.lastBody = '', this.lastBy = '',
      this.unread = 0, this.lastAt, this.otherReadAt});
  factory Conv.of(Map<String, dynamic> m, String me, Map<String, Profile> people) {
    final iamA = m.s('a') == me;
    final other = iamA ? m.s('b') : m.s('a');
    return Conv(
      id: m.s('id'), otherId: other, other: people[other], lastBody: m.s('last_body'), lastBy: m.s('last_by'),
      unread: iamA ? m.i('unread_a') : m.i('unread_b'), lastAt: m.d('last_at'),
      otherReadAt: iamA ? m.d('read_b_at') : m.d('read_a_at'),
    );
  }
}

class Msg {
  final int id;
  final String convId, sender, body, videoId;
  final int replyTo;
  final bool deleted;
  final DateTime? created;
  const Msg({required this.id, required this.convId, required this.sender, this.body = '', this.videoId = '',
      this.replyTo = 0, this.deleted = false, this.created});
  factory Msg.of(Map<String, dynamic> m) => Msg(
        id: m.i('id'), convId: m.s('conv_id'), sender: m.s('sender'), body: m.s('body'), videoId: m.s('video_id'),
        replyTo: m.i('reply_to'), deleted: m.b('deleted'), created: m.d('created_at'));
}

class Notif {
  final int id;
  final String kind, body, videoId;
  final Profile? actor;
  final bool read;
  final DateTime? created;
  const Notif({required this.id, required this.kind, this.body = '', this.videoId = '', this.actor, this.read = false, this.created});
  factory Notif.of(Map<String, dynamic> m) => Notif(
        id: m.i('id'), kind: m.s('kind'), body: m.s('body'), videoId: m.s('video_id'), read: m.b('read'),
        actor: m['profiles'] is Map ? Profile.of(Map<String, dynamic>.from(m['profiles'] as Map)) : null,
        created: m.d('created_at'));
}
