-- Bridge Hub v8: manager can create named (open) devices for others to lock in.
create or replace function public.hub_add_device(p_token text, p_name text) returns public.hub_devices
language plpgsql security definer set search_path = public as $$
declare m hub_devices; d hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager device can add devices'; end if;
  if char_length(trim(p_name)) < 1 or char_length(trim(p_name)) > 40 then raise exception 'Name must be 1-40 characters'; end if;
  if exists (select 1 from hub_devices where user_id = auth.uid() and lower(name) = lower(trim(p_name))) then raise exception 'That name already exists'; end if;
  insert into hub_devices(user_id, name) values (auth.uid(), trim(p_name)) returning * into d;
  return d;
end $$;
grant execute on function public.hub_add_device(text,text) to authenticated;
