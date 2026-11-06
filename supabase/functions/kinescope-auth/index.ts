// Кино Танхим — Kinescope DRM "authorization backend"
// Kinescope лиценз олгохын өмнө энд POST {id, type, token, ip, user_agent} илгээнэ.
// token = сайтын video_token(movie_id)-оор үүсгэсэн, 6 цагийн хүчинтэй HMAC токен.
// 200 → зөвшөөрнө, 403 → татгалзана.
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  let body: { id?: string; token?: string } = {};
  try { body = await req.json(); } catch { return new Response("bad json", { status: 403 }); }
  const token = String(body.token || "");
  if (!token || token.length > 300) return new Response("no token", { status: 403 });
  try {
    const r = await fetch(`${SB_URL}/rest/v1/rpc/check_video_token`, {
      method: "POST",
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_token: token, p_kinescope_id: String(body.id || "") }),
      signal: AbortSignal.timeout(4000),
    });
    const ok = r.ok && (await r.json()) === true;
    return new Response(ok ? "ok" : "denied", { status: ok ? 200 : 403 });
  } catch (e) {
    console.error("check failed", e);
    return new Response("error", { status: 403 });
  }
});
