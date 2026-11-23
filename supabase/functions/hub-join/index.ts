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
    const { data: inv } = await sb.from("hub_invites").select("*").eq("code", code.trim().toUpperCase()).maybeSingle();
    if (!inv || !inv.active) return out({ error: "This invite was turned off or doesn't exist" }, 403);
    if (inv.expires_at && new Date(inv.expires_at) < new Date()) return out({ error: "This invite has expired" }, 403);
    if (inv.max_uses && inv.uses >= inv.max_uses) return out({ error: "This invite has been used up" }, 403);
    const { data: u, error: ue } = await sb.auth.admin.getUserById(inv.user_id);
    if (ue || !u?.user?.email) return out({ error: "Board not found" }, 404);
    const { data: link, error: le } = await sb.auth.admin.generateLink({ type: "magiclink", email: u.user.email });
    if (le) return out({ error: le.message }, 500);
    await sb.from("hub_invites").update({ uses: inv.uses + 1 }).eq("code", inv.code);
    return out({ token_hash: link.properties.hashed_token, board: u.user.user_metadata?.username || u.user.email.split("@")[0] });
  } catch (e) { return out({ error: String(e) }, 500); }
});
