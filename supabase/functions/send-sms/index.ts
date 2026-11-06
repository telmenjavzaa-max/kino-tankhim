// Кино Танхим — Supabase "Send SMS Hook" → CallPro (MessagePro) SMS
// Нууц тохиргоо (Supabase → Edge Functions → Secrets):
//   CALLPRO_KEY       — CallPro-оос өгсөн API key
//   CALLPRO_FROM      — илгээх дугаар (13xxxx / 14xxxx / 15xxxx эсвэл IP72)
//   CALLPRO_ENDPOINT  — (сонголттой) API хаяг, анхдагч https://api.messagepro.mn
//   SEND_SMS_HOOK_SECRET — Supabase Auth Hooks дээр үүсгэсэн "v1,whsec_..." нууц

const KEY = Deno.env.get("CALLPRO_KEY") || "";
const FROM = Deno.env.get("CALLPRO_FROM") || "";
const ENDPOINT = (Deno.env.get("CALLPRO_ENDPOINT") || "https://api.messagepro.mn").replace(/\/$/, "");
const HOOK_SECRET = Deno.env.get("SEND_SMS_HOOK_SECRET") || "";

const fail = (message: string, http_code = 500) =>
  new Response(JSON.stringify({ error: { http_code, message } }), {
    status: http_code, headers: { "Content-Type": "application/json" },
  });

function b64ToBytes(b64: string) {
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}
function bytesToB64(bytes: ArrayBuffer) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)));
}
function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// Standard Webhooks гарын үсэг шалгах
async function verify(req: Request, body: string) {
  const id = req.headers.get("webhook-id");
  const ts = req.headers.get("webhook-timestamp");
  const sigHeader = req.headers.get("webhook-signature");
  if (!id || !ts || !sigHeader || !HOOK_SECRET) return false;
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false; // 5 минутаас хуучин бол татгалзана
  const secret = HOOK_SECRET.replace(/^v1,/, "").replace(/^whsec_/, "");
  const key = await crypto.subtle.importKey("raw", b64ToBytes(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = bytesToB64(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${body}`)));
  return sigHeader.split(" ").some((s) => safeEqual(s.replace(/^v1,/, ""), mac));
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return fail("method", 405);
  const body = await req.text();
  if (!(await verify(req, body))) return fail("Гарын үсэг буруу", 401);
  if (!KEY || !FROM) return fail("CallPro тохиргоо (CALLPRO_KEY / CALLPRO_FROM) алга байна");

  let payload: { user?: { phone?: string }; sms?: { otp?: string } };
  try { payload = JSON.parse(body); } catch { return fail("JSON", 400); }
  const otp = payload.sms?.otp || "";
  // Supabase дугаарыг "97699112233" хэлбэрээр өгдөг → CallPro-д 8 оронтой дугаар
  const digits = String(payload.user?.phone || "").replace(/\D/g, "");
  const to = digits.startsWith("976") && digits.length === 11 ? digits.slice(3) : digits;
  if (!/^\d{8}$/.test(to)) return fail("Зөвхөн Монголын 8 оронтой дугаарт илгээнэ", 400);
  if (!/^\d{4,10}$/.test(otp)) return fail("OTP алга", 400);

  // Кирилл 70 тэмдэгтэд багтана → нэг SMS
  const text = `Kino Tankhim: tany nevtrekh kod ${otp}. 5 minutad khuchintei.`;
  const params = new URLSearchParams({ key: KEY, from: FROM, to, text });

  try {
    const r = await fetch(`${ENDPOINT}/send?${params}`, { signal: AbortSignal.timeout(4500) });
    const raw = await r.text();
    let res: unknown = null; try { res = JSON.parse(raw); } catch { /* текст хариу */ }
    const first = Array.isArray(res) ? res[0] : res as { Result?: string; Reason?: string } | null;
    const result = String((first as { Result?: string })?.Result || "").toUpperCase();
    if (!r.ok || (result && result !== "SUCCESS")) {
      console.error("CallPro error", r.status, raw.slice(0, 300));
      return fail("SMS илгээж чадсангүй. Түр хүлээгээд дахин оролдоно уу.", 502);
    }
    return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("CallPro fetch failed", e);
    return fail("SMS үйлчилгээ хариу өгсөнгүй. Дахин оролдоно уу.", 504);
  }
});
