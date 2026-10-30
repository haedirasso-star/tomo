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
const GH_TOKEN = env("GH_TOKEN"), GH_REPO = env("GH_REPO"), ENCODE_SECRET = env("ENCODE_SECRET");
const r2Ready = () => !!(R2_ACC && R2_AK && R2_SK && R2_BUCKET && R2_PUBLIC);
const encodeReady = () => !!(GH_TOKEN && GH_REPO && ENCODE_SECRET);

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

async function dispatchEncode(id: string, raw: string, out: string) {
  const r = await fetch(`https://api.github.com/repos/${GH_REPO}/dispatches`, {
    method: "POST",
    headers: { Authorization: `Bearer ${GH_TOKEN}`, Accept: "application/vnd.github+json", "User-Agent": "to-api", "Content-Type": "application/json" },
    body: JSON.stringify({ event_type: "video-encode", client_payload: { id, raw, out } }),
  });
  if (!r.ok) throw new HttpErr(502, `GitHub ${r.status}`);
}

/** حذف كل ملفات فيديو من R2 (المضغوط · الأصلي · الغلاف) */
async function delVideoFiles(v: Row) {
  for (const k of [String(v.path ?? ""), String(v.raw_key ?? ""), String(v.poster_path ?? ""), keyOfUrl(String(v.url ?? "")), keyOfUrl(String(v.poster ?? ""))]) {
    if (k) await r2Del(k);
  }
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
      if (!ENCODE_SECRET || b.secret !== ENCODE_SECRET) throw new HttpErr(401, "unauthorized");
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
        const vkey = enc ? `raw/${user.id}/${id}.${ext}` : `v/${user.id}/${id}.${ext}`;
        const ctype = ext === "mov" ? "video/quicktime" : ext === "webm" ? "video/webm" : "video/mp4";
        const pkey = `v/${user.id}/${id}.jpg`;
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
        const vkey = enc ? `raw/${user.id}/${id}.${ext}` : `v/${user.id}/${id}.${ext}`;
        const size = await r2Head(vkey);
        if (!size) throw new HttpErr(409, "لم يكتمل رفع الفيديو — أعد المحاولة");
        if (size > MAX_BYTES) { await r2Del(vkey); throw new HttpErr(400, "الفيديو أكبر من الحد"); }
        const pkey = `v/${user.id}/${id}.jpg`;
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
          try { await dispatchEncode(id, vkey, `v/${user.id}/${id}`); }
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

      case "status":
        return json({ ok: true, storage: r2Ready(), encode: encodeReady() });
    }
    throw new HttpErr(400, "إجراء غير معروف");
  } catch (e) {
    const status = e instanceof HttpErr ? e.status : 500;
    if (status >= 500) console.error(`[${action}]`, e);
    return json({ error: e instanceof Error ? e.message : String(e) }, status);
  }
});
