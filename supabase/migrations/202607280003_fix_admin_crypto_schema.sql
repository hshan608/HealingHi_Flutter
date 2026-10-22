create or replace function private.check_admin_password(p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_installation_id text := public.request_installation_id();
  v_hash text;
  v_attempt private.admin_login_attempts%rowtype;
begin
  if v_installation_id is null then
    return false;
  end if;

  select *
    into v_attempt
    from private.admin_login_attempts
   where installation_id = v_installation_id;

  if v_attempt.locked_until is not null and v_attempt.locked_until > now() then
    return false;
  end if;

  select password_hash
    into v_hash
    from private.admin_config
   where singleton = true;

  if v_hash is not null
    and extensions.crypt(coalesce(p_password, ''), v_hash) = v_hash
  then
    insert into private.admin_login_attempts (
      installation_id,
      failed_count,
      locked_until,
      updated_at
    )
    values (v_installation_id, 0, null, now())
    on conflict (installation_id)
    do update set
      failed_count = 0,
      locked_until = null,
      updated_at = now();
    return true;
  end if;

  insert into private.admin_login_attempts (
    installation_id,
    failed_count,
    locked_until,
    updated_at
  )
  values (v_installation_id, 1, null, now())
  on conflict (installation_id)
  do update set
    failed_count = private.admin_login_attempts.failed_count + 1,
    locked_until = case
      when private.admin_login_attempts.failed_count + 1 >= 5
        then now() + interval '15 minutes'
      else null
    end,
    updated_at = now();

  return false;
end;
$$;

create or replace function public.admin_change_password(
  p_current_password text,
  p_new_password text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.check_admin_password(p_current_password)
    or length(coalesce(p_new_password, '')) < 16
  then
    return false;
  end if;

  update private.admin_config
     set password_hash = extensions.crypt(
           p_new_password,
           extensions.gen_salt('bf', 12)
         ),
         updated_at = now()
   where singleton = true;

  return true;
end;
$$;

revoke all on function public.admin_change_password(text, text) from public;
grant execute on function public.admin_change_password(text, text)
  to anon, authenticated;

notify pgrst, 'reload schema';
