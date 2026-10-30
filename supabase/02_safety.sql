-- ════════════════════════════════════════════════════════════════════
--  02 — الأمان ومنع الإساءة (آمن للتكرار)
--   • الأدوار (user · moderator · admin) والحظر الإداري (banned) — لا يغيّرها المستخدم أبداً
--   • حدود سرعة في الخادم: تعليقات · رسائل · متابعات · بلاغات (ضد البوتات والإزعاج)
--   • الفيديوهات تُنشأ من دالة api فقط (بعد التحقق من الملف في R2) — لا إدراج مباشر من التطبيق
--   • إعدادات عامة يقرؤها التطبيق (app_settings) وخاصة لا يقرؤها إلا الخادم (private_settings)
-- ════════════════════════════════════════════════════════════════════
alter table public.profiles add column if not exists role   text not null default 'user';
alter table public.profiles add column if not exists banned boolean not null default false;
alter table public.profiles add column if not exists onboarded boolean not null default false;
do $$ begin
  alter table public.profiles add constraint profiles_role_chk check (role in ('user', 'moderator', 'admin'));
exception when duplicate_object then null; end $$;
-- المستخدم يعدّل هذه فقط (الدور والحظر والتوثيق والعدّادات للخادم)
revoke update on public.profiles from authenticated;
grant update (username, name, bio, link, avatar, private, dm, birth_year, onboarded) on public.profiles to authenticated;

alter table public.videos add column if not exists raw_key text not null default '';
alter table public.videos add column if not exists size bigint not null default 0;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('moderator', 'admin') and not banned);
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and not banned);
$$;

-- لا إدراج مباشر للفيديوهات من التطبيق
drop policy if exists v_ins on public.videos;
-- المحظور إدارياً لا يظهر محتواه
create or replace function public.can_see(p_user uuid, p_status text, p_privacy text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_user = auth.uid()
      or public.is_staff()
      or (p_status = 'ready'
          and not exists (select 1 from public.profiles where id = p_user and banned)
          and (auth.uid() is null or not public.blocked_between(p_user, auth.uid()))
          and (p_privacy = 'public' or (p_privacy = 'friends' and public.is_friend(p_user, auth.uid()))));
$$;

-- ── حارس عام: محظور ⇐ ممنوع · سرعة أعلى من الحد ⇐ «تمهّل قليلاً» ──
create or replace function public.guard_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
  lim int;
  win interval;
  n int;
begin
  uid := (to_jsonb(new) ->> case tg_table_name
           when 'messages' then 'sender' when 'follows' then 'follower' when 'reports' then 'reporter' else 'user_id' end)::uuid;
  if exists (select 1 from public.profiles where id = uid and banned) then
    raise exception 'حسابك موقوف — تواصل مع الدعم' using errcode = '42501';
  end if;
  case tg_table_name
    when 'comments' then lim := 15;  win := interval '1 minute';
      select count(*) into n from public.comments where user_id = uid and created_at > now() - win;
    when 'messages' then lim := 40;  win := interval '1 minute';
      select count(*) into n from public.messages where sender = uid and created_at > now() - win;
    when 'follows'  then lim := 120; win := interval '1 hour';
      select count(*) into n from public.follows where follower = uid and created_at > now() - win;
    when 'reports'  then lim := 30;  win := interval '1 day';
      select count(*) into n from public.reports where reporter = uid and created_at > now() - win;
    when 'likes'    then lim := 300; win := interval '1 hour';
      select count(*) into n from public.likes where user_id = uid and created_at > now() - win;
  end case;
  if n >= lim then
    raise exception 'تمهّل قليلاً وحاول بعد دقائق' using errcode = 'P0429';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['comments', 'messages', 'follows', 'reports', 'likes'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_guard', t);
    execute format('create trigger %I before insert on public.%I for each row execute function public.guard_insert()', t || '_guard', t);
  end loop;
end $$;

-- ── الإعدادات ───────────────────────────────────────────────────────
create table if not exists public.app_settings (
  key        text primary key,
  value      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
drop policy if exists s_read on public.app_settings;
create policy s_read on public.app_settings for select using (true);
revoke insert, update, delete on public.app_settings from anon, authenticated;

create table if not exists public.private_settings (
  key        text primary key,
  value      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.private_settings enable row level security;
revoke all on public.private_settings from anon, authenticated;

-- ── سجل إجراءات الإدارة (للمراجعة والمساءلة) ──────────────────────────
create table if not exists public.mod_log (
  id         bigint generated always as identity primary key,
  actor      uuid references public.profiles(id) on delete set null,
  action     text not null,
  target     text not null default '',
  note       text not null default '',
  created_at timestamptz not null default now()
);
alter table public.mod_log enable row level security;
drop policy if exists ml_sel on public.mod_log;
create policy ml_sel on public.mod_log for select using (public.is_staff());
revoke insert, update, delete on public.mod_log from anon, authenticated;

-- البلاغات: المشرفون يرونها كلها
drop policy if exists r_sel on public.reports;
create policy r_sel on public.reports for select using (reporter = auth.uid() or public.is_staff());

grant execute on function public.is_staff(), public.is_admin() to authenticated;

-- ── الدخول باسم المستخدم (مثل إنستغرام) ─────────────────────────────
--  يعيد البريد فقط إذا كانت كلمة المرور صحيحة ⇐ لا يمكن معرفة بريد أي حساب من اسمه
--  10 محاولات لكل اسم مستخدم كل 15 دقيقة ⇐ ضد التخمين
create table if not exists public.login_attempts (
  username text not null,
  at       timestamptz not null default now()
);
create index if not exists login_attempts_idx on public.login_attempts (username, at);
alter table public.login_attempts enable row level security;
revoke all on public.login_attempts from anon, authenticated;

create or replace function public.login_email(p_username text, p_password text)
returns text language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  u text := lower(trim(coalesce(p_username, '')));
  em text; pw text;
begin
  if u = '' or coalesce(p_password, '') = '' then return null; end if;
  if (select count(*) from public.login_attempts where username = u and at > now() - interval '15 minutes') >= 10 then
    raise exception 'محاولات كثيرة — انتظر 15 دقيقة ثم حاول مجدداً' using errcode = 'P0429';
  end if;
  insert into public.login_attempts (username) values (u);
  delete from public.login_attempts where at < now() - interval '1 day' and random() < 0.05;
  select au.email, au.encrypted_password into em, pw
    from public.profiles p join auth.users au on au.id = p.id where p.username = u;
  if em is null or pw is null or crypt(p_password, pw) <> pw then return null; end if;
  return em;
end $$;
revoke all on function public.login_email(text, text) from public;
grant execute on function public.login_email(text, text) to anon, authenticated;
