-- ════════════════════════════════════════════════════════════════════
--  03 — الترويج (من نظام إعلانات TOTV المجرَّب) — آمن للتكرار
--
--  صاحب الفيديو يروّج فيديو منشوراً: الميزانية (د.ع) ⇐ الهدف (مشاهدات أو ضغطات على زر) ⇐ زر اختياري
--  ⇐ الدفع بتحويل + صورة الوصل ⇐ مراجعة الإدارة ⇐ يظهر «ممول» بين الفيديوهات ⇐ أرقام دقيقة يومية
--  منع الغش في الخادم: 3 مشاهدات مدفوعة كحد أقصى لكل جهاز يومياً · ضغطة مدفوعة واحدة · مشاهدات صاحب الحملة لا تُحتسب
--  رقم الوصل الرسمي: TO-P-000123
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.promo_campaigns (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  video_id    uuid references public.videos(id) on delete set null,
  objective   text not null default 'views' check (objective in ('views', 'clicks')),
  budget      int  not null check (budget > 0),           -- د.ع
  price       int  not null,                              -- لكل 1000 مشاهدة أو لكل ضغطة (مثبّت عند الطلب)
  bonus_pct   int  not null default 0,
  goal        int  not null default 0,
  days        int  not null default 7,
  cta_label   text not null default '',
  cta_link    text not null default '',
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'active', 'paused', 'done', 'rejected', 'cancelled')),
  pay_status  text not null default 'unpaid' check (pay_status in ('unpaid', 'submitted', 'paid', 'free')),
  pay_method  text not null default '',
  pay_receipt text not null default '',                   -- مسار صورة الوصل في مخزن receipts (خاص)
  pay_txn     text not null default '',
  paid_at     timestamptz,
  reason      text not null default '',
  impressions bigint not null default 0,
  views       bigint not null default 0,
  paid_views  bigint not null default 0,
  uniq        bigint not null default 0,
  completes   bigint not null default 0,
  clicks      bigint not null default 0,
  paid_clicks bigint not null default 0,
  watch_ms    bigint not null default 0,
  skips       bigint not null default 0,
  start_at    timestamptz,
  end_at      timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  approved_at timestamptz,
  done_at     timestamptz
);
create index if not exists promo_user_idx on public.promo_campaigns (user_id, created_at desc);
create index if not exists promo_status_idx on public.promo_campaigns (status);

create table if not exists public.promo_daily (
  cid         bigint not null references public.promo_campaigns(id) on delete cascade,
  day         date not null,
  impressions int not null default 0,
  views       int not null default 0,
  paid_views  int not null default 0,
  uniq        int not null default 0,
  completes   int not null default 0,
  clicks      int not null default 0,
  paid_clicks int not null default 0,
  watch_ms    bigint not null default 0,
  skips       int not null default 0,
  primary key (cid, day)
);
create table if not exists public.promo_seen (
  cid bigint not null,
  dev text not null,
  day date not null,
  v   smallint not null default 0,
  c   smallint not null default 0,
  primary key (cid, dev, day)
);

alter table public.promo_campaigns enable row level security;
alter table public.promo_daily     enable row level security;
alter table public.promo_seen      enable row level security;
drop policy if exists pc_sel on public.promo_campaigns;
create policy pc_sel on public.promo_campaigns for select using (user_id = auth.uid() or public.is_staff());
drop policy if exists pd_sel on public.promo_daily;
create policy pd_sel on public.promo_daily for select
  using (exists (select 1 from public.promo_campaigns c where c.id = cid and (c.user_id = auth.uid() or public.is_staff())));
revoke insert, update, delete on public.promo_campaigns, public.promo_daily from anon, authenticated;
revoke all on public.promo_seen from anon, authenticated;

-- الأسعار الافتراضية (تُعدَّل من لوحة الإدارة)
insert into public.app_settings (key, value) values ('promo_rates', jsonb_build_object(
  'enabled', true, 'cpm', 1000, 'cpc', 150, 'min_budget', 5000, 'max_budget', 5000000,
  'bonus_first', 30, 'max_days', 30, 'usd', 1450,
  'packages', jsonb_build_array(5000, 10000, 25000, 50000, 100000),
  'methods', jsonb_build_array()      -- [{"name":"زين كاش","account":"07xxxxxxxxx","holder":"..."}] تضبطها الإدارة
)) on conflict (key) do nothing;

create or replace function public.promo_rates() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_settings where key = 'promo_rates'), '{}'::jsonb);
$$;

create or replace function public.promo_code(p_id bigint) returns text language sql immutable as $$
  select 'TO-P-' || lpad(p_id::text, 6, '0');
$$;

/** طلب ترويج جديد لفيديو أملكه */
create or replace function public.promo_create(p_video uuid, p_objective text, p_budget int, p_days int,
                                              p_cta_label text default '', p_cta_link text default '')
returns public.promo_campaigns language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  rt jsonb := public.promo_rates();
  v public.videos;
  obj text := case when p_objective = 'clicks' then 'clicks' else 'views' end;
  price int;
  bonus int := 0;
  link text := trim(coalesce(p_cta_link, ''));
  v_row public.promo_campaigns;
begin
  if me is null then raise exception 'سجّل الدخول أولاً'; end if;
  if exists (select 1 from public.profiles where id = me and banned) then raise exception 'حسابك موقوف'; end if;
  if coalesce((rt->>'enabled')::boolean, true) = false then raise exception 'الترويج متوقف مؤقتاً'; end if;
  select * into v from public.videos where id = p_video;
  if not found or v.user_id <> me then raise exception 'يمكنك ترويج فيديوهاتك فقط'; end if;
  if v.status <> 'ready' or v.privacy <> 'public' then raise exception 'الفيديو يجب أن يكون منشوراً للجميع'; end if;
  if p_budget < coalesce((rt->>'min_budget')::int, 5000) then raise exception 'أقل ميزانية % د.ع', rt->>'min_budget'; end if;
  if p_budget > coalesce((rt->>'max_budget')::int, 5000000) then raise exception 'الميزانية أعلى من الحد'; end if;
  if (select count(*) from public.promo_campaigns where user_id = me and status = 'pending' and pay_status = 'unpaid') >= 3 then
    raise exception 'لديك طلبات غير مدفوعة — ادفعها أو ألغها أولاً';
  end if;
  if link <> '' and link !~* '^https?://[^\s]+\.[^\s]+' then
    if link ~* '^[^\s/]+\.[a-z]{2,}' then link := 'https://' || link; else raise exception 'الرابط غير صحيح — مثال: https://example.com'; end if;
  end if;
  if obj = 'clicks' and link = '' then raise exception 'الدفع بالضغطة يحتاج زراً برابط'; end if;
  price := case when obj = 'clicks' then coalesce((rt->>'cpc')::int, 150) else coalesce((rt->>'cpm')::int, 1000) end;
  if not exists (select 1 from public.promo_campaigns where user_id = me and status not in ('cancelled', 'rejected')) then
    bonus := coalesce((rt->>'bonus_first')::int, 0);
  end if;
  insert into public.promo_campaigns (user_id, video_id, objective, budget, price, bonus_pct, goal, days, cta_label, cta_link)
  values (me, p_video, obj, p_budget, price, bonus,
          greatest(1, floor((case when obj = 'clicks' then p_budget::numeric / price else p_budget * 1000.0 / price end) * (1 + bonus / 100.0)))::int,
          least(greatest(coalesce(p_days, 7), 1), coalesce((rt->>'max_days')::int, 30)),
          left(trim(coalesce(p_cta_label, '')), 24), link)
  returning * into v_row;
  return v_row;
end $$;

/** إرسال إثبات الدفع (صورة الوصل مرفوعة مسبقاً في receipts/<me>/...) */
create or replace function public.promo_pay(p_id bigint, p_method text, p_receipt text, p_txn text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_receipt !~ ('^' || auth.uid()::text || '/[A-Za-z0-9_.-]+$') then raise exception 'صورة الوصل غير صالحة'; end if;
  update public.promo_campaigns set pay_status = 'submitted', pay_method = left(coalesce(p_method, ''), 60),
         pay_receipt = p_receipt, pay_txn = left(coalesce(p_txn, ''), 60), paid_at = now(), updated_at = now()
   where id = p_id and user_id = auth.uid() and status = 'pending' and pay_status in ('unpaid', 'submitted');
  if not found then raise exception 'لا يمكن الدفع لهذا الطلب'; end if;
  -- إشعار المشرفين
  insert into public.notifications (user_id, actor, kind, body)
  select id, auth.uid(), 'system', 'طلب ترويج جديد بانتظار المراجعة ' || public.promo_code(p_id)
    from public.profiles where role in ('admin', 'moderator') and not banned;
end $$;

create or replace function public.promo_cancel(p_id bigint) returns void
language sql security definer set search_path = public as $$
  update public.promo_campaigns set status = 'cancelled', updated_at = now()
   where id = p_id and user_id = auth.uid() and status = 'pending' and pay_status in ('unpaid', 'submitted');
$$;

create or replace function public.promo_pause(p_id bigint, p_on boolean) returns void
language sql security definer set search_path = public as $$
  update public.promo_campaigns set status = case when p_on then 'paused' else 'active' end, updated_at = now()
   where id = p_id and user_id = auth.uid() and status = case when p_on then 'active' else 'paused' end;
$$;

/** فيديوهات ممولة لإدراجها بين فيديوهات «لك» — يعرض الحملات الفعّالة الأقرب لإكمال هدفها أولاً بتوزيع عادل */
create or replace function public.promo_pick(p_seen uuid[] default '{}', p_limit int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  -- انتهاء المدة ⇐ اكتملت
  update public.promo_campaigns set status = 'done', done_at = now(), updated_at = now()
   where status = 'active' and end_at is not null and end_at <= now();
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into r from (
    select f.*, c.id as cid, c.cta_label as promo_cta_label, c.cta_link as promo_cta_link
      from public.promo_campaigns c
      join public.feed_items f on f.id = c.video_id
     where c.status = 'active' and f.status = 'ready' and f.privacy = 'public'
       and not (f.id = any (coalesce(p_seen, '{}')))
       and (auth.uid() is null or (c.user_id <> auth.uid() and not public.blocked_between(c.user_id, auth.uid())))
     order by random() * (1.0 - least(0.9, (case when c.objective = 'clicks' then c.paid_clicks else c.paid_views end)::float8 / greatest(c.goal, 1))) desc
     limit least(greatest(p_limit, 1), 3)
  ) x;
  return r;
end $$;

-- ════════════════════════════════════════════════════════════════════
--  trk (نسخة كاملة): أرقام الفيديو + أرقام الحملة مع منع التكرار المدفوع لكل جهاز
--  p = {"d":"<معرّف الجهاز>", "e":[{"t":"i|v|q|w|s|c|k","r":"<video uuid>","c":<cid>,"u":1,"w":<ms>}]}
-- ════════════════════════════════════════════════════════════════════
create or replace function public.trk(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_dev text := left(regexp_replace(coalesce(p->>'d', ''), '[^A-Za-z0-9_.:-]', '', 'g'), 64);
  d date := (now() at time zone 'Asia/Baghdad')::date;
  a record;
  cmp record;
  s_v int; s_c int; pv int; pc int; nu int;
  n int := 0;
begin
  if jsonb_typeof(p->'e') <> 'array' then return 0; end if;
  create temp table if not exists _ev (t text, r uuid, c bigint, u int, w bigint) on commit drop;
  truncate _ev;
  insert into _ev
  select e->>'t', (e->>'r')::uuid,
         case when (e->>'c') ~ '^[0-9]{1,12}$' then (e->>'c')::bigint end,
         case when (e->>'u') = '1' then 1 else 0 end,
         least(greatest(coalesce(case when (e->>'w') ~ '^[0-9]{1,9}$' then (e->>'w')::bigint end, 0), 0), 600000)
    from (select value e from jsonb_array_elements(p->'e') limit 300) x
   where (e->>'t') in ('i', 'v', 'q', 'w', 's', 'c', 'k')
     and coalesce(e->>'r', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  get diagnostics n = row_count;
  if n = 0 then return 0; end if;

  -- ── أرقام الفيديوهات ──
  for a in
    select r, least(count(*) filter (where t = 'v'), 30)::int v, least(sum(u) filter (where t = 'v'), 1)::int u,
           least(count(*) filter (where t = 'q'), 30)::int q, least(coalesce(sum(w) filter (where t = 'w'), 0), 1800000)::bigint w,
           least(count(*) filter (where t = 's'), 3)::int s
      from _ev group by r
  loop
    update public.videos set views = views + a.v, uniq = uniq + coalesce(a.u, 0), completes = completes + a.q,
           watch_ms = watch_ms + a.w, shares = shares + a.s
     where id = a.r;
    if found then
      insert into public.video_daily as x (video_id, day, views, uniq, completes, watch_ms, shares)
      values (a.r, d, a.v, coalesce(a.u, 0), a.q, a.w, a.s)
      on conflict (video_id, day) do update set views = x.views + excluded.views, uniq = x.uniq + excluded.uniq,
        completes = x.completes + excluded.completes, watch_ms = x.watch_ms + excluded.watch_ms, shares = x.shares + excluded.shares;
    end if;
  end loop;

  -- ── أرقام الحملات (المدفوع للحملة الفعّالة فقط · حد التكرار لكل جهاز) ──
  if length(v_dev) >= 6 then
    for a in
      select c, count(*) filter (where t = 'i')::int i, least(count(*) filter (where t = 'v'), 30)::int v,
             least(count(*) filter (where t = 'q'), 30)::int q, least(coalesce(sum(w) filter (where t = 'w'), 0), 1800000)::bigint w,
             least(count(*) filter (where t = 'c'), 5)::int cl, least(count(*) filter (where t = 'k'), 30)::int k
        from _ev where c is not null group by c
    loop
      select id, user_id, status into cmp from public.promo_campaigns where id = a.c;
      if not found then continue; end if;
      s_v := 0; s_c := 0;
      if a.v > 0 or a.cl > 0 then
        insert into public.promo_seen as x (cid, dev, day, v, c) values (a.c, v_dev, d, least(a.v, 999), least(a.cl, 999))
        on conflict (cid, dev, day) do update set v = least(x.v + excluded.v, 999), c = least(x.c + excluded.c, 999)
        returning v, c into s_v, s_c;
      end if;
      nu := case when a.v > 0 and s_v - a.v <= 0 then 1 else 0 end;
      pv := greatest(0, least(s_v, 3) - least(s_v - a.v, 3));
      pc := greatest(0, least(s_c, 1) - least(s_c - a.cl, 1));
      if cmp.status <> 'active' or cmp.user_id = auth.uid() then pv := 0; pc := 0; end if;
      insert into public.promo_daily as x (cid, day, impressions, views, paid_views, uniq, completes, clicks, paid_clicks, watch_ms, skips)
      values (a.c, d, a.i, a.v, pv, nu, a.q, a.cl, pc, a.w, a.k)
      on conflict (cid, day) do update set impressions = x.impressions + excluded.impressions, views = x.views + excluded.views,
        paid_views = x.paid_views + excluded.paid_views, uniq = x.uniq + excluded.uniq, completes = x.completes + excluded.completes,
        clicks = x.clicks + excluded.clicks, paid_clicks = x.paid_clicks + excluded.paid_clicks,
        watch_ms = x.watch_ms + excluded.watch_ms, skips = x.skips + excluded.skips;
      update public.promo_campaigns set
        impressions = impressions + a.i, views = views + a.v, paid_views = paid_views + pv, uniq = uniq + nu,
        completes = completes + a.q, clicks = clicks + a.cl, paid_clicks = paid_clicks + pc, watch_ms = watch_ms + a.w, skips = skips + a.k,
        status = case when status = 'active' and goal > 0 and
                   (case when objective = 'clicks' then paid_clicks + pc else paid_views + pv end) >= goal then 'done' else status end,
        done_at = case when status = 'active' and goal > 0 and
                   (case when objective = 'clicks' then paid_clicks + pc else paid_views + pv end) >= goal then now() else done_at end
       where id = a.c;
    end loop;
    delete from public.promo_seen where day < d - 1 and random() < 0.02;
  end if;
  return n;
end $$;

-- ── مخزن صور الوصولات (خاص: صاحبها والمشرفون فقط) ───────────────────
insert into storage.buckets (id, name, public, file_size_limit) values ('receipts', 'receipts', false, 5242880)
on conflict (id) do update set public = false;
do $$ begin
  drop policy if exists to_receipts_ins on storage.objects;
  create policy to_receipts_ins on storage.objects for insert to authenticated
    with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
  drop policy if exists to_receipts_sel on storage.objects;
  create policy to_receipts_sel on storage.objects for select to authenticated
    using (bucket_id = 'receipts' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));
end $$;

revoke all on function public.trk(jsonb) from public;
grant execute on function public.trk(jsonb) to anon, authenticated;
grant execute on function public.promo_rates(), public.promo_pick(uuid[], int) to anon, authenticated;
grant execute on function public.promo_create(uuid, text, int, int, text, text), public.promo_pay(bigint, text, text, text),
  public.promo_cancel(bigint), public.promo_pause(bigint, boolean) to authenticated;
revoke execute on function public.promo_create(uuid, text, int, int, text, text), public.promo_pay(bigint, text, text, text),
  public.promo_cancel(bigint), public.promo_pause(bigint, boolean) from anon, public;
