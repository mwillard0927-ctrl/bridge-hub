-- Bridge Hub v10: phone push notifications (stores each phone's notification address).
create table if not exists public.hub_push_subs (
  endpoint text primary key,
  user_id uuid not null references auth.users on delete cascade,
  device text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
alter table public.hub_push_subs enable row level security;

create or replace function public.hub_save_push(p_token text, p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null then raise exception 'Pick your name first'; end if;
  insert into hub_push_subs(endpoint, user_id, device, p256dh, auth) values (p_endpoint, auth.uid(), m.name, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = excluded.user_id, device = excluded.device, p256dh = excluded.p256dh, auth = excluded.auth, created_at = now();
end $$;

create or replace function public.hub_remove_push(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from hub_push_subs where endpoint = p_endpoint and user_id = auth.uid();
$$;

grant execute on function public.hub_save_push(text,text,text,text), public.hub_remove_push(text) to authenticated;
