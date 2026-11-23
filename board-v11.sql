-- Bridge Hub v11: revocable invite codes
create table if not exists public.hub_invites(
  code text primary key,
  user_id uuid not null references auth.users on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  max_uses int,
  uses int not null default 0,
  active boolean not null default true);
alter table public.hub_invites enable row level security;
drop policy if exists inv_read on public.hub_invites;
create policy inv_read on public.hub_invites for select to authenticated using (user_id = auth.uid());

create or replace function public.hub_make_invite(p_token text, p_days int, p_max int) returns public.hub_invites
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; c text;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only a manager can make invites'; end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into hub_invites(code,user_id,created_by,expires_at,max_uses)
  values (c, auth.uid(), m.name,
    case when p_days > 0 then now() + make_interval(days => p_days) end,
    case when p_max > 0 then p_max end)
  returning * into i;
  return i;
end $$;
grant execute on function public.hub_make_invite(text,int,int) to authenticated;

create or replace function public.hub_end_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only a manager can turn off invites'; end if;
  update hub_invites set active = false where code = p_code and user_id = auth.uid();
end $$;
grant execute on function public.hub_end_invite(text,text) to authenticated;
grant select on public.hub_invites to authenticated;
