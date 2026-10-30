-- ════════════════════════════════════════════════════════════════════
--  Tomo — قاعدة البيانات الكاملة (Supabase / Postgres) — آمن للتكرار
--
--  الحسابات (profiles) · الفيديوهات (videos) · الإعجاب والحفظ · التعليقات · المتابعة
--  المحادثات الخاصة · الإشعارات · الحظر والإبلاغ · حذف الحساب
--  الخوارزمية: feed_for_you (تفاعل ÷ مشاهدات × حداثة) · feed_following
--  العدّادات الدقيقة: trk (دفعات أحداث من الجهاز — المشاهدة · الإكمال · المشاركة · زمن المشاهدة)
-- ════════════════════════════════════════════════════════════════════
create extension if not exists pgcrypto;

-- ── الملف الشخصي (يُنشأ تلقائياً عند التسجيل) ──────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null unique check (username ~ '^[a-z0-9_.]{3,24}$'),
  name        text not null default '' check (char_length(name) <= 40),
  bio         text not null default '' check (char_length(bio) <= 160),
  link        text not null default '' check (char_length(link) <= 200),
  avatar      text not null default '',
  followers   int  not null default 0,
  following   int  not null default 0,
  likes       bigint not null default 0,     -- مجموع الإعجابات على فيديوهاته
  videos      int  not null default 0,
  private     boolean not null default false,
  dm          text not null default 'friends' check (dm in ('everyone', 'friends', 'none')),
  verified    boolean not null default false,
  birth_year  int,
  created_at  timestamptz not null default now()
);
alter table public.profiles add column if not exists onboarded boolean not null default false;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  base text := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1), 'user'), '[^a-zA-Z0-9_.]', '', 'g'));
  u text;
  n int := 0;
begin
  if char_length(base) < 3 then base := 'user' || base; end if;
  base := left(base, 20);
  u := base;
  while exists (select 1 from public.profiles where username = u) loop
    n := n + 1; u := left(base, 20) || n::text;
  end loop;
  -- البريد: سنة الميلاد والموافقة أثناء التسجيل ⇐ جاهز · غوغل/فيسبوك/آبل ⇐ يكمل حسابه أولاً (onboarded = false)
  insert into public.profiles (id, username, name, birth_year, onboarded, avatar)
  values (new.id, u,
          left(coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', ''), 40),
          nullif(new.raw_user_meta_data->>'birth_year', '')::int,
          coalesce(new.raw_user_meta_data->>'birth_year', '') <> '',
          left(coalesce(new.raw_user_meta_data->>'avatar_url', ''), 500));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ── الفيديوهات ──────────────────────────────────────────────────────
create table if not exists public.videos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  caption     text not null default '' check (char_length(caption) <= 2200),
  tags        text[] not null default '{}',
  url         text not null,
  path        text not null default '',          -- مسار الملف في مخزن videos (للحذف)
  poster      text not null default '',
  poster_path text not null default '',
  duration    int  not null default 0,            -- ثوانٍ
  width       int  not null default 0,
  height      int  not null default 0,
  privacy     text not null default 'public' check (privacy in ('public', 'friends', 'private')),
  allow_comments boolean not null default true,
  allow_duet  boolean not null default true,
  status      text not null default 'ready' check (status in ('processing', 'ready', 'failed', 'removed')),
  -- ★ إعلان ممول (الحملات تُضاف في المرحلة التالية)
  sponsored   boolean not null default false,
  cta_label   text not null default '',
  cta_link    text not null default '',
  -- العدّادات
  views       bigint not null default 0,
  uniq        bigint not null default 0,
  completes   bigint not null default 0,
  watch_ms    bigint not null default 0,
  likes       bigint not null default 0,
  comments    bigint not null default 0,
  shares      bigint not null default 0,
  saves       bigint not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists videos_user_idx on public.videos (user_id, created_at desc);
create index if not exists videos_feed_idx on public.videos (created_at desc) where status = 'ready' and privacy = 'public';
create index if not exists videos_tags_idx on public.videos using gin (tags);

-- ── المتابعة · الإعجاب · الحفظ · التعليقات ───────────────────────────
create table if not exists public.follows (
  follower   uuid not null references public.profiles(id) on delete cascade,
  followee   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);
create index if not exists follows_followee_idx on public.follows (followee);

create table if not exists public.likes (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  video_id   uuid not null references public.videos(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, video_id)
);
create index if not exists likes_video_idx on public.likes (video_id);

create table if not exists public.saves (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  video_id   uuid not null references public.videos(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, video_id)
);

create table if not exists public.comments (
  id         bigint generated always as identity primary key,
  video_id   uuid not null references public.videos(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  parent_id  bigint references public.comments(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  likes      int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists comments_video_idx on public.comments (video_id, created_at desc);

-- ── الحظر والإبلاغ (مطلوبان في آبل ستور وغوغل بلي) ────────────────────
create table if not exists public.blocks (
  blocker    uuid not null references public.profiles(id) on delete cascade,
  blocked    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);
create table if not exists public.reports (
  id         bigint generated always as identity primary key,
  reporter   uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('video', 'user', 'comment', 'message')),
  target     text not null,
  reason     text not null default '',
  status     text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  created_at timestamptz not null default now()
);

-- ── المحادثات الخاصة ────────────────────────────────────────────────
create table if not exists public.conversations (
  id         uuid primary key default gen_random_uuid(),
  a          uuid not null references public.profiles(id) on delete cascade,
  b          uuid not null references public.profiles(id) on delete cascade,
  last_body  text not null default '',
  last_at    timestamptz not null default now(),
  last_by    uuid,
  unread_a   int not null default 0,
  unread_b   int not null default 0,
  read_a_at  timestamptz,
  read_b_at  timestamptz,
  created_at timestamptz not null default now(),
  check (a < b),
  unique (a, b)
);
create table if not exists public.messages (
  id         bigint generated always as identity primary key,
  conv_id    uuid not null references public.conversations(id) on delete cascade,
  sender     uuid not null references public.profiles(id) on delete cascade,
  body       text not null default '' check (char_length(body) <= 2000),
  video_id   uuid references public.videos(id) on delete set null,   -- مشاركة فيديو في المحادثة
  reply_to   bigint,
  deleted    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists messages_conv_idx on public.messages (conv_id, id desc);

-- ── الإشعارات ───────────────────────────────────────────────────────
create table if not exists public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  actor      uuid references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('like', 'comment', 'follow', 'mention', 'system')),
  video_id   uuid references public.videos(id) on delete cascade,
  body       text not null default '',
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notif_user_idx on public.notifications (user_id, id desc);

-- ── عدّادات يومية لكل فيديو (لتحليلات صاحب الفيديو والمعلن) ─────────────
create table if not exists public.video_daily (
  video_id  uuid not null references public.videos(id) on delete cascade,
  day       date not null,
  views     int not null default 0,
  uniq      int not null default 0,
  completes int not null default 0,
  watch_ms  bigint not null default 0,
  shares    int not null default 0,
  primary key (video_id, day)
);

-- ════════════════════════════════════════════════════════════════════
--  المشغّلات: العدّادات والإشعارات تُحدَّث تلقائياً
-- ════════════════════════════════════════════════════════════════════
create or replace function public.blocked_between(x uuid, y uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks where (blocker = x and blocked = y) or (blocker = y and blocked = x));
$$;

create or replace function public.notify(p_user uuid, p_actor uuid, p_kind text, p_video uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user = p_actor then return; end if;
  -- إعجاب/متابعة مكررة خلال ساعة ⇐ إشعار واحد
  if p_kind in ('like', 'follow') and exists (
      select 1 from public.notifications where user_id = p_user and actor = p_actor and kind = p_kind
         and video_id is not distinct from p_video and created_at > now() - interval '1 hour') then return; end if;
  insert into public.notifications (user_id, actor, kind, video_id, body) values (p_user, p_actor, p_kind, p_video, left(coalesce(p_body, ''), 200));
end $$;

create or replace function public.on_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if tg_op = 'INSERT' then
    update public.videos set likes = likes + 1 where id = new.video_id returning user_id into owner;
    update public.profiles set likes = likes + 1 where id = owner;
    perform public.notify(owner, new.user_id, 'like', new.video_id, '');
    return new;
  else
    update public.videos set likes = greatest(likes - 1, 0) where id = old.video_id returning user_id into owner;
    update public.profiles set likes = greatest(likes - 1, 0) where id = owner;
    return old;
  end if;
end $$;
drop trigger if exists likes_count on public.likes;
create trigger likes_count after insert or delete on public.likes for each row execute function public.on_like();

create or replace function public.on_save() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then update public.videos set saves = saves + 1 where id = new.video_id; return new;
  else update public.videos set saves = greatest(saves - 1, 0) where id = old.video_id; return old; end if;
end $$;
drop trigger if exists saves_count on public.saves;
create trigger saves_count after insert or delete on public.saves for each row execute function public.on_save();

create or replace function public.on_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if tg_op = 'INSERT' then
    update public.videos set comments = comments + 1 where id = new.video_id returning user_id into owner;
    perform public.notify(owner, new.user_id, 'comment', new.video_id, new.body);
    return new;
  else
    update public.videos set comments = greatest(comments - 1, 0) where id = old.video_id;
    return old;
  end if;
end $$;
drop trigger if exists comments_count on public.comments;
create trigger comments_count after insert or delete on public.comments for each row execute function public.on_comment();

create or replace function public.on_follow() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set following = following + 1 where id = new.follower;
    update public.profiles set followers = followers + 1 where id = new.followee;
    perform public.notify(new.followee, new.follower, 'follow', null, '');
    return new;
  else
    update public.profiles set following = greatest(following - 1, 0) where id = old.follower;
    update public.profiles set followers = greatest(followers - 1, 0) where id = old.followee;
    return old;
  end if;
end $$;
drop trigger if exists follows_count on public.follows;
create trigger follows_count after insert or delete on public.follows for each row execute function public.on_follow();

create or replace function public.on_video() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set videos = videos + 1 where id = new.user_id;
    -- الوسوم من الوصف: #كلمة
    if new.tags = '{}' then
      new.tags := coalesce((select array_agg(distinct lower(m[1])) from regexp_matches(new.caption, '#([[:alnum:]_]+)', 'g') m), '{}');
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles set videos = greatest(videos - 1, 0), likes = greatest(likes - old.likes, 0) where id = old.user_id;
    return old;
  end if;
  return new;
end $$;
drop trigger if exists videos_before on public.videos;
create trigger videos_before before insert on public.videos for each row execute function public.on_video();
drop trigger if exists videos_after_del on public.videos;
create trigger videos_after_del after delete on public.videos for each row execute function public.on_video();

create or replace function public.on_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.conversations
     set last_body = case when new.video_id is not null and new.body = '' then '🎬 فيديو' else left(new.body, 120) end,
         last_at = new.created_at, last_by = new.sender,
         unread_a = case when a = new.sender then unread_a else unread_a + 1 end,
         unread_b = case when b = new.sender then unread_b else unread_b + 1 end
   where id = new.conv_id;
  return new;
end $$;
drop trigger if exists messages_after on public.messages;
create trigger messages_after after insert on public.messages for each row execute function public.on_message();

-- ════════════════════════════════════════════════════════════════════
--  الصلاحيات (RLS)
-- ════════════════════════════════════════════════════════════════════
alter table public.profiles      enable row level security;
alter table public.videos        enable row level security;
alter table public.follows       enable row level security;
alter table public.likes         enable row level security;
alter table public.saves         enable row level security;
alter table public.comments      enable row level security;
alter table public.blocks        enable row level security;
alter table public.reports       enable row level security;
alter table public.conversations enable row level security;
alter table public.messages      enable row level security;
alter table public.notifications enable row level security;
alter table public.video_daily   enable row level security;

create or replace function public.is_friend(x uuid, y uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.follows where follower = x and followee = y)
     and exists (select 1 from public.follows where follower = y and followee = x);
$$;
create or replace function public.can_see(p_user uuid, p_status text, p_privacy text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_user = auth.uid()
      or (p_status = 'ready'
          and (auth.uid() is null or not public.blocked_between(p_user, auth.uid()))
          and (p_privacy = 'public' or (p_privacy = 'friends' and public.is_friend(p_user, auth.uid()))));
$$;

do $$ begin
  -- profiles
  drop policy if exists p_sel on public.profiles;   create policy p_sel on public.profiles for select using (true);
  drop policy if exists p_upd on public.profiles;   create policy p_upd on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
  -- videos
  drop policy if exists v_sel on public.videos;     create policy v_sel on public.videos for select using (public.can_see(user_id, status, privacy));
  drop policy if exists v_upd on public.videos;     create policy v_upd on public.videos for update using (user_id = auth.uid()) with check (user_id = auth.uid());
  drop policy if exists v_del on public.videos;     create policy v_del on public.videos for delete using (user_id = auth.uid());
  -- follows
  drop policy if exists f_sel on public.follows;    create policy f_sel on public.follows for select using (true);
  drop policy if exists f_ins on public.follows;    create policy f_ins on public.follows for insert with check (follower = auth.uid() and not public.blocked_between(follower, followee));
  drop policy if exists f_del on public.follows;    create policy f_del on public.follows for delete using (follower = auth.uid() or followee = auth.uid());
  -- likes / saves: يرى المستخدم إعجاباته فقط
  drop policy if exists l_sel on public.likes;      create policy l_sel on public.likes for select using (user_id = auth.uid());
  drop policy if exists l_ins on public.likes;      create policy l_ins on public.likes for insert with check (user_id = auth.uid());
  drop policy if exists l_del on public.likes;      create policy l_del on public.likes for delete using (user_id = auth.uid());
  drop policy if exists s_sel on public.saves;      create policy s_sel on public.saves for select using (user_id = auth.uid());
  drop policy if exists s_ins on public.saves;      create policy s_ins on public.saves for insert with check (user_id = auth.uid());
  drop policy if exists s_del on public.saves;      create policy s_del on public.saves for delete using (user_id = auth.uid());
  -- comments
  drop policy if exists c_sel on public.comments;   create policy c_sel on public.comments for select
    using (exists (select 1 from public.videos v where v.id = video_id and public.can_see(v.user_id, v.status, v.privacy)) and not public.blocked_between(user_id, auth.uid()));
  drop policy if exists c_ins on public.comments;   create policy c_ins on public.comments for insert
    with check (user_id = auth.uid() and exists (select 1 from public.videos v where v.id = video_id and v.allow_comments and public.can_see(v.user_id, v.status, v.privacy)));
  drop policy if exists c_del on public.comments;   create policy c_del on public.comments for delete
    using (user_id = auth.uid() or exists (select 1 from public.videos v where v.id = video_id and v.user_id = auth.uid()));
  -- blocks / reports
  drop policy if exists b_sel on public.blocks;     create policy b_sel on public.blocks for select using (blocker = auth.uid());
  drop policy if exists b_ins on public.blocks;     create policy b_ins on public.blocks for insert with check (blocker = auth.uid());
  drop policy if exists b_del on public.blocks;     create policy b_del on public.blocks for delete using (blocker = auth.uid());
  drop policy if exists r_ins on public.reports;    create policy r_ins on public.reports for insert with check (reporter = auth.uid());
  -- conversations / messages: الطرفان فقط
  drop policy if exists cv_sel on public.conversations; create policy cv_sel on public.conversations for select using (auth.uid() in (a, b));
  drop policy if exists m_sel on public.messages;   create policy m_sel on public.messages for select
    using (exists (select 1 from public.conversations c where c.id = conv_id and auth.uid() in (c.a, c.b)));
  drop policy if exists m_ins on public.messages;   create policy m_ins on public.messages for insert
    with check (sender = auth.uid() and exists (select 1 from public.conversations c where c.id = conv_id and auth.uid() in (c.a, c.b)
                and not public.blocked_between(c.a, c.b)));
  drop policy if exists m_upd on public.messages;   create policy m_upd on public.messages for update using (sender = auth.uid()) with check (sender = auth.uid());
  -- notifications
  drop policy if exists n_sel on public.notifications; create policy n_sel on public.notifications for select using (user_id = auth.uid());
  drop policy if exists n_upd on public.notifications; create policy n_upd on public.notifications for update using (user_id = auth.uid());
  -- video_daily: صاحب الفيديو فقط
  drop policy if exists vd_sel on public.video_daily; create policy vd_sel on public.video_daily for select
    using (exists (select 1 from public.videos v where v.id = video_id and v.user_id = auth.uid()));
end $$;

-- المستخدم لا يغيّر عدّاداته ولا التوثيق بنفسه
revoke update on public.profiles from authenticated;
grant update (username, name, bio, link, avatar, private, dm) on public.profiles to authenticated;
revoke update on public.videos from authenticated;
grant update (caption, privacy, allow_comments, allow_duet, poster, poster_path) on public.videos to authenticated;
revoke update on public.messages from authenticated;
grant update (deleted) on public.messages to authenticated;

-- ════════════════════════════════════════════════════════════════════
--  الخوارزمية والدوال
-- ════════════════════════════════════════════════════════════════════
alter table public.videos add column if not exists raw_key text not null default '';
alter table public.videos add column if not exists size bigint not null default 0;
drop view if exists public.feed_items cascade;
create view public.feed_items with (security_invoker = true) as
  select v.*, p.username, p.name as author_name, p.avatar as author_avatar, p.verified as author_verified
    from public.videos v join public.profiles p on p.id = v.user_id;

/** «لك»: نسبة التفاعل إلى المشاهدات × الحداثة + قليل من العشوائية لاكتشاف الجديد. p_seen = ما شاهده الجهاز مؤخراً */
create or replace function public.feed_for_you(p_limit int default 12, p_seen uuid[] default '{}')
returns setof public.feed_items language sql stable security invoker set search_path = public as $$
  select f.* from public.feed_items f
   where f.status = 'ready' and f.privacy = 'public'
     and not (f.id = any (p_seen))
     and (auth.uid() is null or (f.user_id <> auth.uid() and not public.blocked_between(f.user_id, auth.uid())))
   order by (
       (f.likes * 3 + f.comments * 4 + f.shares * 6 + f.saves * 4 + f.completes * 2 + 5)::float8 / (f.views + 25)
       * exp(- extract(epoch from (now() - f.created_at)) / 259200.0)   -- يتلاشى خلال ~3 أيام
       + random() * 0.08
     ) desc
   limit least(greatest(p_limit, 1), 30);
$$;

/** «المتابَعون»: الأحدث ممن يتابعهم المستخدم */
create or replace function public.feed_following(p_limit int default 12, p_before timestamptz default now())
returns setof public.feed_items language sql stable security invoker set search_path = public as $$
  select f.* from public.feed_items f
   where f.status = 'ready' and f.created_at < p_before
     and f.user_id in (select followee from public.follows where follower = auth.uid())
   order by f.created_at desc
   limit least(greatest(p_limit, 1), 30);
$$;

/** أحداث المشاهدة دفعة واحدة من الجهاز: v مشاهدة (u=1 أول مرة اليوم) · q إكمال · w زمن · s مشاركة */
create or replace function public.trk(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  d date := (now() at time zone 'Asia/Baghdad')::date;
  n int := 0;
begin
  if jsonb_typeof(p->'e') <> 'array' then return 0; end if;
  with ev as (
    select (e->>'r')::uuid vid, e->>'t' t, coalesce((e->>'u')::int, 0) u, least(coalesce((e->>'w')::bigint, 0), 600000) w
      from jsonb_array_elements(p->'e') e
     where e->>'r' ~ '^[0-9a-f-]{36}$'
     limit 300
  ), agg as (
    select vid, count(*) filter (where t = 'v') v, sum(u) filter (where t = 'v') u, count(*) filter (where t = 'q') q,
           coalesce(sum(w) filter (where t = 'w'), 0) w, count(*) filter (where t = 's') s
      from ev group by vid
  ), up as (
    update public.videos x set views = views + a.v, uniq = uniq + coalesce(a.u, 0), completes = completes + a.q,
           watch_ms = watch_ms + a.w, shares = shares + a.s
      from agg a where x.id = a.vid returning x.id
  ), dd as (
    insert into public.video_daily (video_id, day, views, uniq, completes, watch_ms, shares)
    select a.vid, d, a.v, coalesce(a.u, 0), a.q, a.w, a.s from agg a where exists (select 1 from public.videos x where x.id = a.vid)
    on conflict (video_id, day) do update set views = video_daily.views + excluded.views, uniq = video_daily.uniq + excluded.uniq,
      completes = video_daily.completes + excluded.completes, watch_ms = video_daily.watch_ms + excluded.watch_ms,
      shares = video_daily.shares + excluded.shares
    returning 1
  )
  select count(*) into n from up;
  return n;
end $$;

/** فتح محادثة: المتابعة المتبادلة أو من يسمح بالرسائل للجميع */
create or replace function public.open_conv(p_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  x uuid; y uuid; cid uuid; pref text;
begin
  if me is null then raise exception 'سجّل الدخول أولاً'; end if;
  if p_other = me then raise exception 'لا يمكن مراسلة نفسك'; end if;
  if public.blocked_between(me, p_other) then raise exception 'لا يمكن المراسلة'; end if;
  x := least(me, p_other); y := greatest(me, p_other);
  select id into cid from public.conversations where a = x and b = y;
  if cid is not null then return cid; end if;
  select dm into pref from public.profiles where id = p_other;
  if pref = 'none' or (pref = 'friends' and not public.is_friend(me, p_other)) then
    raise exception 'هذا الحساب يستقبل الرسائل من الأصدقاء فقط (متابعة متبادلة)';
  end if;
  insert into public.conversations (a, b) values (x, y) returning id into cid;
  return cid;
end $$;

create or replace function public.read_conv(p_conv uuid)
returns void language sql security definer set search_path = public as $$
  update public.conversations
     set unread_a = case when a = auth.uid() then 0 else unread_a end,
         unread_b = case when b = auth.uid() then 0 else unread_b end,
         read_a_at = case when a = auth.uid() then now() else read_a_at end,
         read_b_at = case when b = auth.uid() then now() else read_b_at end
   where id = p_conv and auth.uid() in (a, b);
$$;

/** حذف الحساب نهائياً (مطلوب في المتاجر) — الملفات تُحذف من التطبيق قبل الاستدعاء */
create or replace function public.delete_me()
returns void language sql security definer set search_path = public, auth as $$
  delete from auth.users where id = auth.uid();
$$;

/** البحث عن حسابات */
create or replace function public.search_users(p_q text, p_limit int default 20)
returns setof public.profiles language sql stable security invoker set search_path = public as $$
  select * from public.profiles
   where (username ilike '%' || p_q || '%' or name ilike '%' || p_q || '%')
     and (auth.uid() is null or not public.blocked_between(id, auth.uid()))
   order by followers desc limit least(greatest(p_limit, 1), 50);
$$;

/** اقتراحات للمتابعة: الأكثر متابعة ممن لا تتابعهم */
create or replace function public.suggested_users(p_limit int default 20)
returns setof public.profiles language sql stable security invoker set search_path = public as $$
  select * from public.profiles p
   where p.id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
     and p.videos > 0
     and not exists (select 1 from public.follows f where f.follower = auth.uid() and f.followee = p.id)
     and (auth.uid() is null or not public.blocked_between(p.id, auth.uid()))
   order by p.followers desc, p.created_at desc limit least(greatest(p_limit, 1), 50);
$$;

revoke all on function public.trk(jsonb) from public;
grant execute on function public.trk(jsonb) to anon, authenticated;
grant execute on function public.feed_for_you(int, uuid[]) to anon, authenticated;
grant execute on function public.feed_following(int, timestamptz) to authenticated;
grant execute on function public.open_conv(uuid), public.read_conv(uuid), public.delete_me() to authenticated;
revoke execute on function public.delete_me() from anon, public;
grant execute on function public.search_users(text, int), public.suggested_users(int) to anon, authenticated;
grant select on public.feed_items to anon, authenticated;

-- ── الرسائل الفورية ─────────────────────────────────────────────────
do $$ begin
  begin alter publication supabase_realtime add table public.messages; exception when others then null; end;
  begin alter publication supabase_realtime add table public.conversations; exception when others then null; end;
end $$;

-- ════════════════════════════════════════════════════════════════════
--  التخزين: videos (عام) · avatars (عام) — كل مستخدم يكتب في مجلده فقط
-- ════════════════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public, file_size_limit)
values ('videos', 'videos', true, 209715200), ('avatars', 'avatars', true, 5242880)
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit;

do $$ begin
  drop policy if exists tomo_media_ins on storage.objects;
  create policy tomo_media_ins on storage.objects for insert to authenticated
    with check (bucket_id in ('videos', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists tomo_media_upd on storage.objects;
  create policy tomo_media_upd on storage.objects for update to authenticated
    using (bucket_id in ('videos', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists tomo_media_del on storage.objects;
  create policy tomo_media_del on storage.objects for delete to authenticated
    using (bucket_id in ('videos', 'avatars') and (storage.foldername(name))[1] = auth.uid()::text);
end $$;
