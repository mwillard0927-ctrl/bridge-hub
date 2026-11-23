-- v15: lowering the seed pool trims open QRs and people's caps to fit
create or replace function public.hub_set_seed(p_token text, p_total int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; l int;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager sets the seed pool'; end if;
  insert into hub_seed(user_id, total) values (auth.uid(), case when p_total > 0 then p_total end)
  on conflict (user_id) do update set total = excluded.total;
  if p_total > 0 then
    l := greatest(p_total - hub_seed_used(auth.uid()), 0);
    -- open QRs: no more new joins than what's left, pass-on no bigger than what's left
    update hub_invites set
      max_uses = least(coalesce(max_uses, uses + l), uses + l),
      can_pass = least(can_pass, greatest(l - 1, 0))
    where user_id = auth.uid() and active;
    -- people's caps: no more room than what's left
    update hub_devices d set pool = least(d.pool, hub_used(d.id) + l)
    where d.user_id = auth.uid() and not d.is_manager;
  end if;
end $$;
grant execute on function public.hub_set_seed(text,int) to authenticated;
