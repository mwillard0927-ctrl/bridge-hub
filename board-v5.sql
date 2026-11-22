-- Bridge Hub v5: read tracking visible ONLY to each login's manager device.
-- Run AFTER board-v4.sql. Safe to run more than once.
alter table public.hub_devices add column if not exists last_seen timestamptz;

create table if not exists public.hub_file_opens (
  post_id uuid references public.hub_posts on delete cascade,
  project_id uuid references public.hub_projects on delete cascade,
  user_id uuid references auth.users on delete cascade,
  device text not null,
  file_path text not null,
  opened_at timestamptz not null default now(),
  primary key (file_path, user_id, device)
);
alter table public.hub_file_opens enable row level security;  -- no policies: only reachable through the functions below

-- views are no longer readable directly (only the manager sees who read what)
revoke select on public.hub_views from authenticated;

-- every device: mark "I'm here" (called when the app opens / comes back)
create or replace function public.hub_ping(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin update hub_devices set last_seen = now() where user_id = auth.uid() and token_hash = hub_h(p_token); end $$;

-- every device: which posts have *I* (this device) opened — for my own NEW badges
create or replace function public.hub_my_views(p_token text) returns table(post_id uuid, project_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null then return; end if;
  return query select v.post_id, v.project_id from hub_views v where v.user_id = auth.uid() and v.device = m.name;
end $$;

-- every device: record that it opened a file
create or replace function public.hub_file_open(p_token text, p_post uuid, p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_posts;
begin
  m := hub_me(p_token); if m.id is null then return; end if;
  select * into p from hub_posts where id = p_post;
  if p.id is null or not hub_is_member(p.project_id) or not hub_can_see(p, m.name) then return; end if;
  insert into hub_file_opens(post_id, project_id, user_id, device, file_path) values (p.id, p.project_id, auth.uid(), m.name, p_path)
  on conflict (file_path, user_id, device) do update set opened_at = excluded.opened_at;
end $$;

-- MANAGER ONLY: full tracking for a board
create or replace function public.hub_tracking(p_token text, p_project uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager or not hub_is_member(p_project) then return null; end if;
  return json_build_object(
    'views',   coalesce((select json_agg(json_build_object('post_id', post_id, 'user_id', user_id, 'device', device, 'at', viewed_at)) from hub_views where project_id = p_project), '[]'::json),
    'opens',   coalesce((select json_agg(json_build_object('post_id', post_id, 'user_id', user_id, 'device', device, 'path', file_path, 'at', opened_at)) from hub_file_opens where project_id = p_project), '[]'::json),
    'devices', coalesce((select json_agg(json_build_object('name', name, 'last_seen', last_seen)) from hub_devices where user_id = auth.uid()), '[]'::json));
end $$;

grant execute on function public.hub_ping(text), public.hub_my_views(text), public.hub_file_open(text,uuid,text), public.hub_tracking(text,uuid) to authenticated;
