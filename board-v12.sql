-- Bridge Hub v12: turning off an invite blocks the users who joined with it
alter table public.hub_devices add column if not exists invite_code text;

create or replace function public.hub_me(p_token text) returns public.hub_devices
language sql stable security definer set search_path = public as $$
  select d.* from hub_devices d
  where d.user_id = auth.uid() and d.token_hash = hub_h(p_token)
    and (d.invite_code is null or exists (select 1 from hub_invites i where i.code = d.invite_code and i.active))
  limit 1;
$$;

create or replace function public.hub_tag_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update hub_devices set invite_code = upper(p_code)
  where user_id = auth.uid() and token_hash = hub_h(p_token) and not is_manager and invite_code is null
    and exists (select 1 from hub_invites i where i.code = upper(p_code) and i.user_id = auth.uid() and i.active);
end $$;
grant execute on function public.hub_tag_invite(text,text) to authenticated;

create or replace function public.hub_invite_ok(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from hub_invites where code = upper(p_code) and user_id = auth.uid() and active);
$$;
grant execute on function public.hub_invite_ok(text) to authenticated;
