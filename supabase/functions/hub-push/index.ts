// Bridge Hub push sender. Triggered by a Database Webhook on INSERT into hub_posts and hub_replies.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
webpush.setVapidDetails("mailto:admin@setitontheshelf.com", Deno.env.get("VAPID_PUBLIC")!, Deno.env.get("VAPID_PRIVATE")!);

const lc = (s: string) => (s || "").toLowerCase();
const inList = (list: string[] | null, name: string) => !list || list.some((x) => lc(x) === lc(name));
const tagged = (text: string, name: string) => new RegExp("@" + name.trim().replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\s+/g, "_?") + "(?![\\w])", "i").test(text || "");

Deno.serve(async (req) => {
  if (req.headers.get("x-hook-secret") !== Deno.env.get("HOOK_SECRET")) return new Response("forbidden", { status: 403 });
  const { type, table, record: r } = await req.json();
  if (type !== "INSERT" || !r) return new Response("skip");

  let post = r, title = "", body = "", text = "";
  if (table === "hub_replies") {
    const { data } = await sb.from("hub_posts").select("*").eq("id", r.post_id).single();
    if (!data) return new Response("no post");
    post = data;
    title = `${r.device || "Someone"} replied to “${post.title}”`;
    body = (r.body || "").slice(0, 140);
    text = r.body || "";
  } else if (table === "hub_posts") {
    const kind = { poll: "a poll", checklist: "a checklist", event: "an event" }[r.ptype as string] || "a post";
    title = `${r.device || "Someone"} added ${kind}`;
    body = r.title + (r.body ? " — " + r.body.slice(0, 100) : "");
    text = (r.title || "") + " " + (r.body || "");
  } else return new Response("skip");

  const { data: proj } = await sb.from("hub_projects").select("name, allowed").eq("id", post.project_id).single();
  const { data: mem } = await sb.from("hub_members").select("user_id").eq("project_id", post.project_id);
  const users = (mem || []).map((m: any) => m.user_id);
  if (!users.length) return new Response("no members");
  const { data: subs } = await sb.from("hub_push_subs").select("*").in("user_id", users);

  const sends = (subs || []).filter((s: any) =>
    !(s.user_id === r.user_id && lc(s.device) === lc(r.device)) &&
    inList(proj?.allowed ?? null, s.device) &&
    inList(post.recipients ?? null, s.device)
  ).map(async (s: any) => {
    const isTag = tagged(text, s.device);
    const payload = JSON.stringify({
      title: (isTag ? "🏷 " : "") + title + (proj?.name ? ` · ${proj.name}` : ""),
      body: isTag ? "You were tagged: " + body : body,
      tag: post.id,
      url: "https://setitontheshelf.com/",
    });
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload);
    } catch (e: any) {
      if (e?.statusCode === 404 || e?.statusCode === 410) await sb.from("hub_push_subs").delete().eq("endpoint", s.endpoint);
    }
  });
  await Promise.all(sends);
  return new Response(`sent ${sends.length}`);
});
