// ════════════════════════════════════════════════════════════════════
//  دالة api — كل ما يحتاج مفاتيح سرية (لا تغادر الخادم أبداً)
//
//  media_init     ⇐ روابط رفع موقّعة مؤقتة إلى Cloudflare R2 (الفيديو + الغلاف) — الرفع مباشرة من الهاتف
//  media_publish  ⇐ يتحقق من الملف في R2 ثم ينشئ صف الفيديو (المستخدم لا يُدرج فيديوهات بنفسه)
//                   الضغط مفعّل ⇐ «قيد المعالجة» ويُرسل لـ GitHub (720p · faststart) ثم encode_done
//  video_delete   ⇐ يحذف الملفات من R2 ثم الصف
//  account_delete ⇐ يحذف كل ملفات المستخدم ثم حسابه نهائياً (متطلب آبل وغوغل)
//
//  أسرار: R2_ACCOUNT_ID · R2_ACCESS_KEY_ID · R2_SECRET_ACCESS_KEY · R2_BUCKET · R2_PUBLIC_URL
//  (اختياري للضغط) GH_TOKEN · GH_REPO · ENCODE_SECRET
//  تلقائية من Supabase: SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY
// ════════════════════════════════════════════════════════════════════
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const SB_URL = env("SUPABASE_URL");
const SRK = env("SUPABASE_SERVICE_ROLE_KEY");
const R2_ACC = env("R2_ACCOUNT_ID"), R2_AK = env("R2_ACCESS_KEY_ID"), R2_SK = env("R2_SECRET_ACCESS_KEY");
const R2_BUCKET = env("R2_BUCKET");
const R2_PUBLIC = env("R2_PUBLIC_URL").replace(/\/+$/, "");
// ★ الجسر مع TOTV: نفس مخزن R2 (مجلد tomo/ منفصل) · الضغط عبر GitHub · طلبات الترويج في تطبيق إدارة TOTV
const BRIDGE = env("TOTV_BRIDGE_SECRET");
const TOTV_PUSH = env("TOTV_PUSH_URL") || "https://hlmaksidfqdarwunedqj.supabase.co/functions/v1/push";
const ENCODE = env("ENCODE_ENABLED") !== "0";
const PREFIX = (env("R2_PREFIX") || "tomo").replace(/^\/+|\/+$/g, "");
// غوغل: عميل الويب لمشروع Firebase الخاص بـ TOTV (+ أي معرّفات إضافية مفصولة بفاصلة)
const GOOGLE_AUD = ["214530463737-bbqctoe8ftblj1gtfgdgcvrincrncv3q.apps.googleusercontent.com", ...env("GOOGLE_CLIENT_IDS").split(",")].map((x) => x.trim()).filter(Boolean);
const r2Ready = () => !!(R2_ACC && R2_AK && R2_SK && R2_BUCKET && R2_PUBLIC);
const encodeReady = () => !!(BRIDGE && ENCODE);
const safeEq = (a: string, b: string) => {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
};
async function hmacHex(key: string, data: string) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return [...new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(data)))].map((x) => x.toString(16).padStart(2, "0")).join("");
}
async function totv(op: string, body: Row) {
  const r = await fetch(TOTV_PUSH, { method: "POST", headers: { "Content-Type": "application/json", "x-bridge": BRIDGE },
    body: JSON.stringify({ action: "bridge", op, ...body }) });
  if (!r.ok) throw new HttpErr(502, `TOTV ${r.status}: ${(await r.text()).slice(0, 120)}`);
  return r.json();
}

const MAX_BYTES = 200 * 1024 * 1024;
const MAX_PER_DAY = 25;
const VIDEO_EXT = new Set(["mp4", "mov", "m4v", "webm", "3gp", "mkv"]);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
class HttpErr extends Error {
  constructor(public status: number, msg: string) { super(msg); }
}
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });
type Row = Record<string, unknown>;
const int = (v: unknown, d = 0) => { const n = Number(v); return Number.isFinite(n) ? Math.trunc(n) : d; };
const clip = (v: unknown, n: number) => String(v ?? "").trim().slice(0, n);
const isUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(s);

// ── قاعدة البيانات بمفتاح الخدمة ─────────────────────────────────────
async function db(path: string, init: { method?: string; body?: unknown; prefer?: string } = {}): Promise<unknown> {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, {
    method: init.method ?? "GET",
    headers: {
      apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json",
      ...(init.prefer ? { Prefer: init.prefer } : {}),
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const t = await r.text();
  if (!r.ok) throw new HttpErr(502, `DB ${r.status}: ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}

async function userOf(req: Request): Promise<{ id: string; email: string } | null> {
  const tok = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!tok || tok === SRK) return null;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: SRK, Authorization: `Bearer ${tok}` } });
  if (!r.ok) return null;
  const u = await r.json() as Row;
  return u?.id ? { id: String(u.id), email: String(u.email ?? "") } : null;
}

// ── Cloudflare R2 (توقيع S3 SigV4 — نفس آلية TOTV المجرّبة) ───────────
async function sha256hex(t: string) {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(t));
  return [...new Uint8Array(h)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
async function hmac(key: BufferSource, data: string): Promise<ArrayBuffer> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return crypto.subtle.sign("HMAC", k, new TextEncoder().encode(data));
}
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const awsEnc = (s: string) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
const keyPath = (key: string) => key.split("/").map(awsEnc).join("/");

async function r2Presign(method: string, key: string, expires = 900, signed: Record<string, string> = {}): Promise<string> {
  const amzDate = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const day = amzDate.slice(0, 8);
  const scope = `${day}/auto/s3/aws4_request`;
  const host = `${R2_ACC}.r2.cloudflarestorage.com`;
  const hdrs: Record<string, string> = { host, ...Object.fromEntries(Object.entries(signed).map(([k, v]) => [k.toLowerCase(), v.trim()])) };
  const names = Object.keys(hdrs).sort();
  const qs: Record<string, string> = {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256", "X-Amz-Credential": `${R2_AK}/${scope}`, "X-Amz-Date": amzDate,
    "X-Amz-Expires": String(expires), "X-Amz-SignedHeaders": names.join(";"),
  };
  const cq = Object.keys(qs).sort().map((k) => `${awsEnc(k)}=${awsEnc(qs[k])}`).join("&");
  const path = `/${R2_BUCKET}/${keyPath(key)}`;
  const creq = [method, path, cq, names.map((n) => `${n}:${hdrs[n]}\n`).join(""), names.join(";"), "UNSIGNED-PAYLOAD"].join("\n");
  const sts = ["AWS4-HMAC-SHA256", amzDate, scope, await sha256hex(creq)].join("\n");
  let k = await hmac(new TextEncoder().encode(`AWS4${R2_SK}`), day);
  k = await hmac(k, "auto"); k = await hmac(k, "s3"); k = await hmac(k, "aws4_request");
  return `https://${host}${path}?${cq}&X-Amz-Signature=${hex(await hmac(k, sts))}`;
}
async function r2Head(key: string): Promise<number> {
  const r = await fetch(await r2Presign("HEAD", key, 300), { method: "HEAD" });
  return r.ok ? Number(r.headers.get("content-length") ?? 0) || 1 : 0;
}
async function r2Del(key: string) {
  if (!key || !r2Ready()) return;
  try { await fetch(await r2Presign("DELETE", key, 300), { method: "DELETE" }); } catch (e) { console.warn("[r2 del]", e); }
}
const pub = (key: string) => key ? `${R2_PUBLIC}/${keyPath(key)}` : "";
const keyOfUrl = (u: string) => u.startsWith(`${R2_PUBLIC}/`) ? decodeURIComponent(u.slice(R2_PUBLIC.length + 1)) : "";

/** الضغط: TOTV يرسل الطلب إلى GitHub (مستودع tomo) بمفتاحه — لا مفاتيح GitHub هنا */
async function dispatchEncode(id: string, raw: string, out: string) {
  await totv("encode", { id, raw, out });
}

/** حذف كل ملفات فيديو من R2 (المضغوط · الأصلي · الغلاف) */
async function delVideoFiles(v: Row) {
  for (const k of [String(v.path ?? ""), String(v.raw_key ?? ""), String(v.poster_path ?? ""), keyOfUrl(String(v.url ?? "")), keyOfUrl(String(v.poster ?? ""))]) {
    if (k) await r2Del(k);
  }
}

/** الحساب الرسمي @totv داخل Tomo (تظهر باسمه ريلز TOTV) — يُنشأ مرة واحدة */
async function officialId(): Promise<string> {
  const ex = ((await db("profiles?select=id&username=eq.totv")) as Row[])[0];
  if (ex) return String(ex.id);
  const H = { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json" };
  const pw = crypto.randomUUID() + crypto.randomUUID();
  const r = await fetch(`${SB_URL}/auth/v1/admin/users`, { method: "POST", headers: H, body: JSON.stringify({
    email: "official-totv@tomo.app", password: pw, email_confirm: true,
    user_metadata: { username: "totv", name: "TOTV+", birth_year: "2000" },
  }) });
  const u = await r.json() as Row;
  const id = String(u.id ?? "");
  if (!id) throw new HttpErr(502, "تعذّر إنشاء الحساب الرسمي");
  await db(`profiles?id=eq.${id}`, { method: "PATCH", prefer: "return=minimal", body: {
    verified: true, onboarded: true, name: "TOTV+", bio: "أفلام · مسلسلات · مباريات — الحساب الرسمي لـ TOTV+",
  } });
  return id;
}

/** ① ريلز TOTV ⇐ Tomo (باسم @totv) · ② فيديوهات Tomo ⇐ ريلز TOTV */
async function syncWithTotv() {
  const out = { totv_in: 0, totv_removed: 0, tomo_out: 0 };
  // ── ① من TOTV: القائمة العامة على R2 (نفس ما يقرؤه تطبيق TOTV) ──
  const base = R2_PUBLIC || "https://cdn.totv.app";
  const fr = await fetch(`${base}/feeds/reels.json?t=${Date.now()}`);
  if (fr.ok) {
    const items = ((await fr.json()) as Row).items as Row[] ?? [];
    const keep = items.filter((r) => r.ready !== false && r.active !== false && r.kind !== "ad" && r.sponsored !== true
      && !(int(r.cid) > 0) && String(r.video ?? "").startsWith("https://") && !String(r.video).includes(".m3u8")
      && !String(r.id ?? "").startsWith("tm_"));
    const owner = await officialId();
    const have = (await db("videos?select=id,ext_id&source=eq.totv&limit=2000")) as Row[];
    const haveIds = new Set(have.map((h) => String(h.ext_id)));
    const want = new Set(keep.map((r) => `totv:${r.id}`));
    const fresh = keep.filter((r) => !haveIds.has(`totv:${r.id}`)).slice(0, 100).map((r) => ({
      user_id: owner, source: "totv", ext_id: `totv:${r.id}`, status: "ready", privacy: "public", allow_comments: true,
      caption: clip([r.title, r.desc].filter((x) => String(x ?? "").trim()).join("\n"), 2200),
      url: String(r.video), poster: String(r.poster ?? ""), duration: int(r.length),
      created_at: String(r.created ?? "") || new Date().toISOString(),
    }));
    if (fresh.length) await db("videos", { method: "POST", prefer: "return=minimal", body: fresh });
    out.totv_in = fresh.length;
    const gone = have.filter((h) => !want.has(String(h.ext_id))).map((h) => String(h.id));
    for (let i = 0; i < gone.length; i += 50) {
      await db(`videos?id=in.(${gone.slice(i, i + 50).join(",")})`, { method: "DELETE", prefer: "return=minimal" });
    }
    out.totv_removed = gone.length;
  }
  // ── ② إلى TOTV: أحدث فيديوهات Tomo العامة ──
  if (BRIDGE) {
    const list = (await db("rpc/share_list", { method: "POST", body: { p_limit: 150 } })) as Row[];
    const r = await totv("tomo_reels", { items: list.map((v) => ({
      id: String(v.id), title: clip(v.caption, 200), video: String(v.url), poster: String(v.poster ?? ""),
      length: int(v.duration), user: String(v.username ?? ""), created: String(v.created_at ?? ""),
    })) }) as Row;
    out.tomo_out = int(r.count);
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let b: Row = {};
  try { b = await req.json(); } catch { /* */ }
  const action = String(b.action ?? "");
  try {
    // ════ من GitHub بعد الضغط (بسرّ مشترك) ════
    if (action === "encode_done") {
      // توقيع لكل فيديو: HMAC(السر المشترك, id) — يصل من مستودع totv-sports بعد الضغط
      const sigOk = BRIDGE && safeEq(String(b.sig ?? ""), await hmacHex(BRIDGE, String(b.id ?? "")));
      if (!sigOk && !safeEq(String(b.secret ?? ""), BRIDGE)) throw new HttpErr(401, "unauthorized");
      const id = clip(b.id, 40);
      if (!isUuid(id)) throw new HttpErr(400, "id");
      const v = ((await db(`videos?select=id,raw_key,path&id=eq.${id}`)) as Row[])[0];
      if (!v) return json({ ok: true, gone: true });
      if (b.ok === true) {
        const vk = clip(b.video_key, 200), pk = clip(b.poster_key, 200);
        await db(`videos?id=eq.${id}`, { method: "PATCH", prefer: "return=minimal", body: {
          status: "ready", url: pub(vk), path: vk, poster: pub(pk), poster_path: pk, raw_key: "",
          duration: int(b.length), size: int(b.size), ...(int(b.width) > 0 ? { width: int(b.width), height: int(b.height) } : {}),
        } });
        await r2Del(String(v.raw_key ?? ""));
      } else {
        // فشل الضغط ⇐ ننشر الأصلي كما هو بدل أن يضيع الفيديو
        const raw = String(v.raw_key ?? "");
        await db(`videos?id=eq.${id}`, { method: "PATCH", prefer: "return=minimal", body: raw
          ? { status: "ready", url: pub(raw), path: raw, raw_key: "" } : { status: "failed" } });
      }
      return json({ ok: true });
    }

    // ════ من تطبيق إدارة TOTV عبر دالة push (بالسر المشترك) ════
    if (action.startsWith("bridge_")) {
      if (!safeEq(req.headers.get("x-bridge") ?? "", BRIDGE)) throw new HttpErr(401, "unauthorized");
      const rpc = (fn: string, args: Row) => db(`rpc/${fn}`, { method: "POST", body: args });
      switch (action) {
        case "bridge_promos":
          return json({ ok: true, items: await rpc("promo_list", { p_status: clip(b.status, 20) || "review" }) });
        case "bridge_promo_set":
          await rpc("promo_apply", { p_id: int(b.id), p_op: clip(b.op, 20), p_note: clip(b.note, 300), p_actor: null, p_by: clip(b.by, 120) });
          return json({ ok: true });
        case "bridge_receipt": {
          const path = clip(b.path, 300);
          if (!/^[0-9a-f-]{36}\/[A-Za-z0-9_.-]+$/.test(path)) throw new HttpErr(400, "path");
          const r = await fetch(`${SB_URL}/storage/v1/object/sign/receipts/${path}`, {
            method: "POST", headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json" },
            body: JSON.stringify({ expiresIn: 600 }),
          });
          const j = await r.json() as Row;
          if (!r.ok || !j.signedURL) throw new HttpErr(404, "الوصل غير موجود");
          return json({ ok: true, url: `${SB_URL}/storage/v1${j.signedURL}` });
        }
        // ════ تبادل الفيديوهات مع TOTV (كل 15 دقيقة من GitHub) ════
        case "bridge_sync":
          return json({ ok: true, ...(await syncWithTotv()) });
        case "bridge_stats":
          return json({ ok: true, stats: await (async () => {
            const c = (q: string) => db(q).then((x) => (x as Row[]).length).catch(() => 0);
            return {
              review: await c("promo_campaigns?select=id&status=eq.pending&pay_status=in.(submitted,paid,free)"),
              active: await c("promo_campaigns?select=id&status=eq.active"),
            };
          })() });
      }
      throw new HttpErr(400, "bridge?");
    }

    // ════ الدخول بحساب غوغل (عميل Firebase الخاص بـ TOTV) ════
    //  الهاتف يحصل على id_token من غوغل ⇐ نتحقق منه هنا ⇐ ننشئ الحساب إن لم يوجد ⇐ رمز دخول لمرة واحدة
    if (action === "google_login") {
      const tok = clip(b.id_token, 4096);
      if (!tok) throw new HttpErr(400, "id_token");
      const r = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(tok)}`);
      const g = await r.json() as Row;
      if (!r.ok || !GOOGLE_AUD.includes(String(g.aud ?? "")) || !["accounts.google.com", "https://accounts.google.com"].includes(String(g.iss ?? ""))
          || String(g.email_verified) !== "true" || !g.email || int(g.exp) * 1000 < Date.now()) {
        throw new HttpErr(401, "تعذّر التحقق من حساب غوغل");
      }
      const email = String(g.email).toLowerCase();
      const H = { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json" };
      // إنشاء الحساب (إن وُجد مسبقاً يرجع خطأ ونكمل)
      await fetch(`${SB_URL}/auth/v1/admin/users`, { method: "POST", headers: H, body: JSON.stringify({
        email, email_confirm: true,
        user_metadata: { name: clip(g.name, 40), full_name: clip(g.name, 40), avatar_url: clip(g.picture, 400), provider: "google" },
      }) });
      const l = await fetch(`${SB_URL}/auth/v1/admin/generate_link`, { method: "POST", headers: H, body: JSON.stringify({ type: "magiclink", email }) });
      const lk = await l.json() as Row;
      const hashed = String(lk.hashed_token ?? (lk.properties as Row | undefined)?.hashed_token ?? "");
      if (!l.ok || !hashed) throw new HttpErr(502, "تعذّر إنشاء جلسة الدخول");
      return json({ ok: true, token_hash: hashed });
    }

    const user = await userOf(req);
    if (!user) throw new HttpErr(401, "سجّل الدخول أولاً");
    const me = ((await db(`profiles?select=id,role,banned&id=eq.${user.id}`)) as Row[])[0];
    if (!me) throw new HttpErr(403, "الحساب غير موجود");
    const staff = me.role === "admin" || me.role === "moderator";

    switch (action) {
      // ════ روابط الرفع ════
      case "media_init": {
        if (!r2Ready()) throw new HttpErr(503, "التخزين غير مضبوط بعد");
        if (me.banned === true) throw new HttpErr(403, "حسابك موقوف");
        const ext = clip(b.ext, 5).toLowerCase().replace(/[^a-z0-9]/g, "");
        const size = int(b.size);
        if (!VIDEO_EXT.has(ext)) throw new HttpErr(400, "صيغة الفيديو غير مدعومة");
        if (size <= 0 || size > MAX_BYTES) throw new HttpErr(400, "الفيديو أكبر من 200MB");
        const since = new Date(Date.now() - 86400_000).toISOString();
        const today = (await db(`videos?select=id&user_id=eq.${user.id}&created_at=gte.${since}`)) as Row[];
        if (today.length >= MAX_PER_DAY) throw new HttpErr(429, "وصلت حد النشر اليومي — جرّب غداً");
        const id = crypto.randomUUID();
        const enc = encodeReady();
        const vkey = enc ? `${PREFIX}/raw/${user.id}/${id}.${ext}` : `${PREFIX}/v/${user.id}/${id}.${ext}`;
        const ctype = ext === "mov" ? "video/quicktime" : ext === "webm" ? "video/webm" : "video/mp4";
        const pkey = `${PREFIX}/v/${user.id}/${id}.jpg`;
        return json({
          ok: true, id, ext,
          video: { url: await r2Presign("PUT", vkey, 3 * 3600), type: ctype },
          poster: { url: await r2Presign("PUT", pkey, 3 * 3600), type: "image/jpeg" },
        });
      }

      case "media_publish": {
        if (!r2Ready()) throw new HttpErr(503, "التخزين غير مضبوط بعد");
        if (me.banned === true) throw new HttpErr(403, "حسابك موقوف");
        const id = clip(b.id, 40);
        const ext = clip(b.ext, 5).toLowerCase().replace(/[^a-z0-9]/g, "");
        if (!isUuid(id) || !VIDEO_EXT.has(ext)) throw new HttpErr(400, "طلب غير صالح");
        const enc = encodeReady();
        const vkey = enc ? `${PREFIX}/raw/${user.id}/${id}.${ext}` : `${PREFIX}/v/${user.id}/${id}.${ext}`;
        const size = await r2Head(vkey);
        if (!size) throw new HttpErr(409, "لم يكتمل رفع الفيديو — أعد المحاولة");
        if (size > MAX_BYTES) { await r2Del(vkey); throw new HttpErr(400, "الفيديو أكبر من الحد"); }
        const pkey = `${PREFIX}/v/${user.id}/${id}.jpg`;
        const hasPoster = b.poster === true && (await r2Head(pkey)) > 0;
        const privacy = ["public", "friends", "private"].includes(String(b.privacy)) ? String(b.privacy) : "public";
        const row: Row = {
          id, user_id: user.id, caption: clip(b.caption, 2200), privacy, allow_comments: b.allow_comments !== false,
          duration: Math.max(0, Math.min(int(b.duration), 600)), width: Math.max(0, int(b.width)), height: Math.max(0, int(b.height)),
          size, poster: hasPoster ? pub(pkey) : "", poster_path: hasPoster ? pkey : "",
          ...(enc ? { status: "processing", raw_key: vkey, url: pub(vkey), path: "" } : { status: "ready", url: pub(vkey), path: vkey }),
        };
        await db("videos", { method: "POST", prefer: "return=minimal", body: row });
        if (enc) {
          try { await dispatchEncode(id, vkey, `${PREFIX}/v/${user.id}/${id}`); }
          catch (e) {
            console.warn("[encode]", e);
            await db(`videos?id=eq.${id}`, { method: "PATCH", prefer: "return=minimal", body: { status: "ready", path: vkey, raw_key: "" } });
          }
        }
        return json({ ok: true, id, processing: enc });
      }

      case "video_delete": {
        const id = clip(b.id, 40);
        if (!isUuid(id)) throw new HttpErr(400, "id");
        const v = ((await db(`videos?select=*&id=eq.${id}`)) as Row[])[0];
        if (!v) return json({ ok: true });
        if (v.user_id !== user.id && !staff) throw new HttpErr(403, "غير مسموح");
        await db(`videos?id=eq.${id}`, { method: "DELETE", prefer: "return=minimal" });
        await delVideoFiles(v);
        return json({ ok: true });
      }

      case "account_delete": {
        const vids = (await db(`videos?select=*&user_id=eq.${user.id}`)) as Row[];
        for (const v of vids) await delVideoFiles(v);
        // صور الملف والوصولات في تخزين Supabase
        for (const bucket of ["avatars", "receipts"]) {
          try {
            const r = await fetch(`${SB_URL}/storage/v1/object/list/${bucket}`, {
              method: "POST", headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json" },
              body: JSON.stringify({ prefix: `${user.id}/`, limit: 1000 }),
            });
            const files = r.ok ? (await r.json() as Row[]) : [];
            if (files.length) {
              await fetch(`${SB_URL}/storage/v1/object/${bucket}`, {
                method: "DELETE", headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, "Content-Type": "application/json" },
                body: JSON.stringify({ prefixes: files.map((f) => `${user.id}/${f.name}`) }),
              });
            }
          } catch (e) { console.warn("[delete files]", e); }
        }
        const r = await fetch(`${SB_URL}/auth/v1/admin/users/${user.id}`, { method: "DELETE", headers: { apikey: SRK, Authorization: `Bearer ${SRK}` } });
        if (!r.ok) throw new HttpErr(502, "تعذّر حذف الحساب — حاول لاحقاً");
        return json({ ok: true });
      }

      // إشعار تطبيق إدارة TOTV بطلب ترويج جديد
      case "promo_notify": {
        const id = int(b.id);
        const c = ((await db(`promo_campaigns?select=id,user_id,budget,pay_status&id=eq.${id}`)) as Row[])[0];
        if (!c || c.user_id !== user.id || c.pay_status !== "submitted") return json({ ok: true });
        if (BRIDGE) {
          try { await totv("notify", { code: `TO-P-${String(id).padStart(6, "0")}`, budget: int(c.budget) }); } catch (e) { console.warn("[notify]", e); }
        }
        return json({ ok: true });
      }

      case "status":
        return json({ ok: true, storage: r2Ready(), encode: encodeReady(), bridge: !!BRIDGE });
    }
    throw new HttpErr(400, "إجراء غير معروف");
  } catch (e) {
    const status = e instanceof HttpErr ? e.status : 500;
    if (status >= 500) console.error(`[${action}]`, e);
    return json({ error: e instanceof Error ? e.message : String(e) }, status);
  }
});
