-- ════════════════════════════════════════════════════════════════════
--  04 — لوحة الإدارة داخل التطبيق (للمالك والمشرفين فقط) — آمن للتكرار
--   • مراجعة طلبات الترويج والوصولات (موافقة · رفض · مدفوع · مجاني · إيقاف · إنهاء)
--   • البلاغات: إزالة الفيديو/التعليق · إيقاف الحساب · رفض البلاغ (المتاجر تطلب المراجعة خلال 24 ساعة)
--   • الأسعار وطرق الدفع
--  كل إجراء يُسجَّل في mod_log ويُرسل إشعاراً للمستخدم المعني
--  تعيين أول مدير (مرة واحدة من SQL Editor):  update profiles set role = 'admin' where username = 'اسمك';
-- ════════════════════════════════════════════════════════════════════

-- النسخة الداخلية (يستدعيها المشرف من التطبيق، أو تطبيق إدارة TOTV عبر الجسر بمفتاح الخدمة)
create or replace function public.promo_list(p_status text default 'review')
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into r from (
    select c.*, public.promo_code(c.id) as code, p.username, p.name, v.poster, v.url, v.caption
      from public.promo_campaigns c
      join public.profiles p on p.id = c.user_id
      left join public.videos v on v.id = c.video_id
     where case p_status
             when 'review' then c.status = 'pending' and c.pay_status in ('submitted', 'paid', 'free')
             when 'unpaid' then c.status = 'pending' and c.pay_status = 'unpaid'
             when 'active' then c.status in ('active', 'paused', 'approved')
             when 'done'   then c.status in ('done', 'rejected', 'cancelled')
             else true end
     order by c.created_at desc limit 200
  ) x;
  return r;
end $$;

create or replace function public.admin_promos(p_status text default 'review')
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'غير مسموح'; end if;
  return public.promo_list(p_status);
end $$;

create or replace function public.admin_promo_set(p_id bigint, p_op text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'غير مسموح'; end if;
  perform public.promo_apply(p_id, p_op, p_note, auth.uid(), '');
end $$;

/** تنفيذ قرار على طلب ترويج — p_by: من نفّذ (بريد مشرف TOTV عند القرار من تطبيق الإدارة) */
create or replace function public.promo_apply(p_id bigint, p_op text, p_note text, p_actor uuid, p_by text)
returns void language plpgsql security definer set search_path = public as $$
declare
  c public.promo_campaigns;
  msg text := '';
begin
  select * into c from public.promo_campaigns where id = p_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  case p_op
    when 'approve' then
      update public.promo_campaigns set status = 'active', approved_at = now(), start_at = now(), end_at = now() + make_interval(days => days),
             pay_status = case when pay_status = 'free' then 'free' else 'paid' end, updated_at = now() where id = p_id;
      msg := 'بدأ ترويج فيديوك الآن (' || public.promo_code(p_id) || '). تابع الأرقام من «ترويجاتي».';
    when 'free' then
      update public.promo_campaigns set status = 'active', pay_status = 'free', approved_at = now(), start_at = now(),
             end_at = now() + make_interval(days => days), updated_at = now() where id = p_id;
      msg := 'هدية من الإدارة 🎁 بدأ ترويج فيديوك مجاناً (' || public.promo_code(p_id) || ').';
    when 'reject' then
      update public.promo_campaigns set status = 'rejected', reason = left(p_note, 300), updated_at = now() where id = p_id;
      msg := 'لم تتم الموافقة على طلب الترويج ' || public.promo_code(p_id) || case when p_note <> '' then ': ' || p_note else '' end;
    when 'unpaid' then
      update public.promo_campaigns set pay_status = 'unpaid', reason = left(p_note, 300), updated_at = now() where id = p_id;
      msg := 'لم نجد التحويل لطلب ' || public.promo_code(p_id) || ' — أعد إرسال الوصل الصحيح.';
    when 'pause' then
      update public.promo_campaigns set status = 'paused', updated_at = now() where id = p_id and status = 'active';
    when 'resume' then
      update public.promo_campaigns set status = 'active', updated_at = now() where id = p_id and status = 'paused';
    when 'end' then
      update public.promo_campaigns set status = 'done', done_at = now(), updated_at = now() where id = p_id and status in ('active', 'paused', 'approved');
      msg := 'انتهى ترويج ' || public.promo_code(p_id) || '. التقرير الكامل في «ترويجاتي».';
    else raise exception 'إجراء غير معروف';
  end case;
  insert into public.mod_log (actor, action, target, note)
  values (p_actor, 'promo_' || p_op, p_id::text, left(concat_ws(' · ', nullif(p_by, ''), nullif(p_note, '')), 300));
  if msg <> '' then
    insert into public.notifications (user_id, actor, kind, body) values (c.user_id, null, 'system', msg);
  end if;
end $$;

create or replace function public.admin_reports(p_status text default 'open')
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_staff() then raise exception 'غير مسموح'; end if;
  select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) into r from (
    select rp.*, pr.username as reporter_name,
           (select count(*) from public.reports o where o.kind = rp.kind and o.target = rp.target and o.status = 'open') as same,
           case rp.kind
             when 'video' then (select jsonb_build_object('caption', v.caption, 'url', v.url, 'poster', v.poster, 'user_id', v.user_id, 'username', u.username)
                                  from public.videos v join public.profiles u on u.id = v.user_id where v.id::text = rp.target)
             when 'comment' then (select jsonb_build_object('body', cm.body, 'user_id', cm.user_id, 'username', u.username)
                                  from public.comments cm join public.profiles u on u.id = cm.user_id where cm.id::text = rp.target)
             when 'message' then (select jsonb_build_object('body', m.body, 'user_id', m.sender, 'username', u.username)
                                  from public.messages m join public.profiles u on u.id = m.sender where m.id::text = rp.target)
             when 'user' then (select jsonb_build_object('user_id', u.id, 'username', u.username, 'bio', u.bio, 'avatar', u.avatar)
                                  from public.profiles u where u.id::text = rp.target)
           end as content
      from public.reports rp join public.profiles pr on pr.id = rp.reporter
     where rp.status = p_status
     order by rp.created_at limit 200
  ) x;
  return r;
end $$;

/** p_op: remove (إزالة المحتوى) · ban (إيقاف صاحب المحتوى) · dismiss (لا مخالفة) */
create or replace function public.admin_report_set(p_id bigint, p_op text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare
  rp public.reports;
  owner uuid;
begin
  if not public.is_staff() then raise exception 'غير مسموح'; end if;
  select * into rp from public.reports where id = p_id;
  if not found then raise exception 'البلاغ غير موجود'; end if;
  owner := case rp.kind
    when 'video' then (select user_id from public.videos where id::text = rp.target)
    when 'comment' then (select user_id from public.comments where id::text = rp.target)
    when 'message' then (select sender from public.messages where id::text = rp.target)
    when 'user' then (select id from public.profiles where id::text = rp.target) end;
  if p_op in ('remove', 'ban') then
    if rp.kind = 'video' then update public.videos set status = 'removed' where id::text = rp.target;
    elsif rp.kind = 'comment' then delete from public.comments where id::text = rp.target;
    elsif rp.kind = 'message' then update public.messages set deleted = true where id::text = rp.target;
    end if;
    if owner is not null then
      insert into public.notifications (user_id, kind, body) values (owner, 'system',
        'أُزيل محتوى لك لمخالفته إرشادات المجتمع' || case when p_note <> '' then ': ' || p_note else '' end);
    end if;
  end if;
  if p_op = 'ban' and owner is not null then
    if (select role from public.profiles where id = owner) = 'admin' then raise exception 'لا يمكن إيقاف مدير'; end if;
    update public.profiles set banned = true where id = owner;
  end if;
  update public.reports set status = case when p_op = 'dismiss' then 'dismissed' else 'actioned' end
   where kind = rp.kind and target = rp.target and status = 'open';
  insert into public.mod_log (actor, action, target, note) values (auth.uid(), 'report_' || p_op, rp.kind || ':' || rp.target, left(p_note, 300));
end $$;

create or replace function public.admin_ban(p_user uuid, p_on boolean, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'للمدير فقط'; end if;
  if p_user = auth.uid() then raise exception 'لا يمكنك إيقاف نفسك'; end if;
  update public.profiles set banned = p_on where id = p_user and role <> 'admin';
  insert into public.mod_log (actor, action, target, note) values (auth.uid(), case when p_on then 'ban' else 'unban' end, p_user::text, left(p_note, 300));
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'للمدير فقط'; end if;
  if p_role not in ('user', 'moderator', 'admin') then raise exception 'دور غير صالح'; end if;
  update public.profiles set role = p_role where id = p_user;
  insert into public.mod_log (actor, action, target, note) values (auth.uid(), 'role', p_user::text, p_role);
end $$;

create or replace function public.admin_verify(p_user uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'للمدير فقط'; end if;
  update public.profiles set verified = p_on where id = p_user;
  insert into public.mod_log (actor, action, target) values (auth.uid(), case when p_on then 'verify' else 'unverify' end, p_user::text);
end $$;

/** حفظ إعداد عام (الأسعار وطرق الدفع) */
create or replace function public.admin_setting(p_key text, p_value jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'للمدير فقط'; end if;
  if p_key not in ('promo_rates', 'app') then raise exception 'مفتاح غير مسموح'; end if;
  insert into public.app_settings (key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into public.mod_log (actor, action, target) values (auth.uid(), 'setting', p_key);
end $$;

/** أرقام سريعة للوحة */
create or replace function public.admin_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'غير مسموح'; end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'users_today', (select count(*) from public.profiles where created_at > now() - interval '1 day'),
    'videos', (select count(*) from public.videos where status = 'ready'),
    'videos_today', (select count(*) from public.videos where created_at > now() - interval '1 day'),
    'views_today', (select coalesce(sum(views), 0) from public.video_daily where day = (now() at time zone 'Asia/Baghdad')::date),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'promos_review', (select count(*) from public.promo_campaigns where status = 'pending' and pay_status in ('submitted', 'paid', 'free')),
    'promos_active', (select count(*) from public.promo_campaigns where status = 'active'),
    'revenue_month', (select coalesce(sum(budget), 0) from public.promo_campaigns
                       where pay_status = 'paid' and approved_at > date_trunc('month', now()))
  );
end $$;

do $$
declare f text;
begin
  revoke all on function public.promo_list(text) from public, anon, authenticated;
  revoke all on function public.promo_apply(bigint, text, text, uuid, text) from public, anon, authenticated;
  grant execute on function public.promo_list(text), public.promo_apply(bigint, text, text, uuid, text) to service_role;
  foreach f in array array['admin_promos(text)', 'admin_promo_set(bigint, text, text)', 'admin_reports(text)',
                           'admin_report_set(bigint, text, text)', 'admin_ban(uuid, boolean, text)', 'admin_set_role(uuid, text)',
                           'admin_verify(uuid, boolean)', 'admin_setting(text, jsonb)', 'admin_stats()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
