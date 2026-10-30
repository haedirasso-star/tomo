-- ════════════════════════════════════════════════════════════════════
--  05 — تبادل الفيديوهات مع TOTV (آمن للتكرار)
--   source = 'tomo' (نُشر هنا) أو 'totv' (ريل من TOTV يظهر هنا باسم الحساب الرسمي @totv)
--   ext_id = معرّف الريل في TOTV (لمنع التكرار ولحذفه هنا إذا حُذف هناك)
-- ════════════════════════════════════════════════════════════════════
alter table public.videos add column if not exists source text not null default 'tomo';
alter table public.videos add column if not exists ext_id text;
create unique index if not exists videos_ext_idx on public.videos (ext_id) where ext_id is not null;
create index if not exists videos_source_idx on public.videos (source, created_at desc);

-- قائمة فيديوهات Tomo التي تظهر في TOTV: منشورة للجميع · جاهزة · صاحبها غير موقوف · بلا بلاغات مفتوحة كثيرة
create or replace function public.share_list(p_limit int default 150)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select v.id, v.caption, v.url, v.poster, v.duration, v.width, v.height, v.created_at, p.username, p.name
      from public.videos v join public.profiles p on p.id = v.user_id
     where v.source = 'tomo' and v.status = 'ready' and v.privacy = 'public' and not p.banned and not p.private
       and (select count(*) from public.reports r where r.kind = 'video' and r.target = v.id::text and r.status = 'open') < 3
     order by v.created_at desc limit least(greatest(p_limit, 1), 300)
  ) x;
$$;
revoke all on function public.share_list(int) from public, anon, authenticated;
grant execute on function public.share_list(int) to service_role;
