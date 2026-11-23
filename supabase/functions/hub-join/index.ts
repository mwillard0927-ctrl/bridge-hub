// hub-join: trade an invite code for a sign-in (no password needed)
import { createClient } from "npm:@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "content-type, authorization, apikey", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const out = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { code } = await req.json();
    if (!code || typeof code !== "string") return out({ error: "No invite code" }, 400);
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: uid, error: re } = await sb.rpc("hub_redeem", { p_code: code.trim().toUpperCase() });
    if (re || !uid) return out({ error: re?.message || "This invite doesn't work" }, 403);
    const { data: u, error: ue } = await sb.auth.admin.getUserById(uid);
    if (ue || !u?.user?.email) return out({ error: "Board not found" }, 404);
    const { data: link, error: le } = await sb.auth.admin.generateLink({ type: "magiclink", email: u.user.email });
    if (le) return out({ error: le.message }, 500);
    return out({ token_hash: link.properties.hashed_token, board: u.user.user_metadata?.username || u.user.email.split("@")[0] });
  } catch (e) { return out({ error: String(e) }, 500); }
});
