create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function public.request_installation_id()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(
    (
      coalesce(
        nullif(current_setting('request.headers', true), ''),
        '{}'
      )::jsonb ->> 'x-installation-id'
    ),
    ''
  );
$$;

revoke all on function public.request_installation_id() from public;
grant execute on function public.request_installation_id() to anon, authenticated;

create or replace function public.claim_legacy_installation(
  p_legacy_device_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_installation_id text := public.request_installation_id();
  v_user_idx integer;
begin
  if v_installation_id is null
    or v_installation_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or p_legacy_device_id is null
    or p_legacy_device_id = ''
    or p_legacy_device_id = v_installation_id
    or now() >= timestamptz '2026-10-01 00:00:00+00'
  then
    return false;
  end if;

  if exists (
    select 1 from public.users where device_id = v_installation_id
  ) then
    return true;
  end if;

  select idx
    into v_user_idx
    from public.users
   where device_id = p_legacy_device_id
   for update;

  if v_user_idx is null then
    return false;
  end if;

  update public.users
     set device_id = v_installation_id,
         updated_at = now()
   where idx = v_user_idx;

  update public.device_shares
     set device_id = v_installation_id,
         updated_at = now()
   where device_id = p_legacy_device_id;

  update public.request_quotes
     set device_id = v_installation_id
   where device_id = p_legacy_device_id;

  return true;
exception
  when unique_violation then
    return false;
end;
$$;

revoke all on function public.claim_legacy_installation(text) from public;
grant execute on function public.claim_legacy_installation(text)
  to anon, authenticated;

create or replace function public.is_nickname_available(p_user_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select length(trim(coalesce(p_user_id, ''))) between 1 and 30
    and not exists (
      select 1
        from public.users
       where user_id = trim(p_user_id)
         and device_id <> public.request_installation_id()
    );
$$;

revoke all on function public.is_nickname_available(text) from public;
grant execute on function public.is_nickname_available(text)
  to anon, authenticated;

create or replace function public.get_share_leaderboard()
returns table (
  rank bigint,
  display_name text,
  share_count integer,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    rank() over (
      order by coalesce(ds.share_count, 0) desc, u.created_at asc, u.idx asc
    ) as rank,
    u.user_id as display_name,
    coalesce(ds.share_count, 0)::integer as share_count,
    u.device_id = public.request_installation_id() as is_current_user
  from public.users u
  left join public.device_shares ds on ds.device_id = u.device_id
  order by share_count desc, u.created_at asc, u.idx asc
  limit 100;
$$;

revoke all on function public.get_share_leaderboard() from public;
grant execute on function public.get_share_leaderboard()
  to anon, authenticated;

create or replace function public.increment_share_count(p_device_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_installation_id text := public.request_installation_id();
begin
  if v_installation_id is null
    or p_device_id is distinct from v_installation_id
  then
    raise exception 'invalid installation identity';
  end if;

  insert into public.device_shares (device_id, share_count)
  values (v_installation_id, 1)
  on conflict (device_id)
  do update set
    share_count = public.device_shares.share_count + 1,
    updated_at = now();
end;
$$;

revoke all on function public.increment_share_count(text) from public;
grant execute on function public.increment_share_count(text)
  to anon, authenticated;

create table if not exists private.admin_config (
  singleton boolean primary key default true check (singleton),
  password_hash text not null,
  updated_at timestamptz not null default now()
);

insert into private.admin_config (singleton, password_hash)
values (
  true,
  '$2a$12$gY7Z6sRUCXgqhg63Z4slAOw7WofGNqHL1qk9Xb16xe2ulZVa/xCBC'
)
on conflict (singleton)
do update set
  password_hash = excluded.password_hash,
  updated_at = now();

create table if not exists private.admin_login_attempts (
  installation_id text primary key,
  failed_count integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

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

create or replace function public.admin_login(p_password text)
returns boolean
language sql
volatile
security definer
set search_path = ''
as $$
  select private.check_admin_password(p_password);
$$;

create or replace function public.admin_get_pending_quotes(p_password text)
returns table (
  id bigint,
  text_kr text,
  text_eng text,
  resoner_kr text,
  resoner_eng text,
  tag_kr text,
  tag_eng text,
  imagefile text,
  device_id text,
  created_at timestamptz,
  is_accept integer,
  applicant_name text,
  image_url text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.check_admin_password(p_password) then
    raise exception 'invalid admin credentials';
  end if;

  return query
  select
    rq.id,
    rq.text_kr,
    rq.text_eng,
    rq.resoner_kr,
    rq.resoner_eng,
    rq.tag_kr,
    rq.tag_eng,
    rq.imagefile,
    rq.device_id,
    rq.created_at,
    rq.is_accept,
    coalesce(u.user_id, '익명') as applicant_name,
    rqi.image_url
  from public.request_quotes rq
  left join public.users u on u.device_id = rq.device_id
  left join lateral (
    select image_row.image_url
      from public.request_quote_images image_row
     where image_row.request_quote_idx = rq.id
     order by image_row.id desc
     limit 1
  ) rqi on true
  where rq.is_accept is null
  order by rq.created_at asc;
end;
$$;

create or replace function public.admin_approve_quote(
  p_password text,
  p_request_id bigint
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_request public.request_quotes%rowtype;
begin
  if not private.check_admin_password(p_password) then
    raise exception 'invalid admin credentials';
  end if;

  select *
    into v_request
    from public.request_quotes
   where id = p_request_id
     and is_accept is null
   for update;

  if not found then
    return false;
  end if;

  insert into public.quotes (
    id,
    text_kr,
    text_eng,
    resoner_kr,
    resoner_eng,
    tag_kr,
    tag_eng,
    imagefile
  )
  values (
    'req_' || v_request.id,
    v_request.text_kr,
    v_request.text_eng,
    v_request.resoner_kr,
    v_request.resoner_eng,
    v_request.tag_kr,
    v_request.tag_eng,
    v_request.imagefile
  )
  on conflict (id) do nothing;

  update public.request_quotes
     set is_accept = 1
   where id = v_request.id;

  return true;
end;
$$;

create or replace function public.admin_reject_quote(
  p_password text,
  p_request_id bigint
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.check_admin_password(p_password) then
    raise exception 'invalid admin credentials';
  end if;

  update public.request_quotes
     set is_accept = 0
   where id = p_request_id
     and is_accept is null;

  return found;
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

revoke all on function public.admin_login(text) from public;
revoke all on function public.admin_get_pending_quotes(text) from public;
revoke all on function public.admin_approve_quote(text, bigint) from public;
revoke all on function public.admin_reject_quote(text, bigint) from public;
revoke all on function public.admin_change_password(text, text) from public;
grant execute on function public.admin_login(text) to anon, authenticated;
grant execute on function public.admin_get_pending_quotes(text)
  to anon, authenticated;
grant execute on function public.admin_approve_quote(text, bigint)
  to anon, authenticated;
grant execute on function public.admin_reject_quote(text, bigint)
  to anon, authenticated;
grant execute on function public.admin_change_password(text, text)
  to anon, authenticated;

do $$
declare
  p record;
begin
  for p in
    select schemaname, tablename, policyname
      from pg_policies
     where schemaname = 'public'
       and tablename in (
         'users',
         'users_quotes',
         'quotes',
         'device_shares',
         'request_quotes',
         'request_quote_images'
       )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      p.policyname,
      p.schemaname,
      p.tablename
    );
  end loop;
end
$$;

alter table public.users enable row level security;
alter table public.users_quotes enable row level security;
alter table public.quotes enable row level security;
alter table public.device_shares enable row level security;
alter table public.request_quotes enable row level security;
alter table public.request_quote_images enable row level security;

create policy users_select_own
on public.users for select
to anon, authenticated
using (device_id = public.request_installation_id());

create policy users_insert_own
on public.users for insert
to anon, authenticated
with check (device_id = public.request_installation_id());

create policy users_update_own
on public.users for update
to anon, authenticated
using (device_id = public.request_installation_id())
with check (device_id = public.request_installation_id());

create policy users_quotes_select_own
on public.users_quotes for select
to anon, authenticated
using (
  exists (
    select 1
      from public.users
     where users.idx = users_quotes.user_idx
       and users.device_id = public.request_installation_id()
  )
);

create policy users_quotes_insert_own
on public.users_quotes for insert
to anon, authenticated
with check (
  exists (
    select 1
      from public.users
     where users.idx = users_quotes.user_idx
       and users.device_id = public.request_installation_id()
  )
  and exists (
    select 1 from public.quotes where quotes.id = users_quotes.quotes_id
  )
);

create policy users_quotes_update_own
on public.users_quotes for update
to anon, authenticated
using (
  exists (
    select 1
      from public.users
     where users.idx = users_quotes.user_idx
       and users.device_id = public.request_installation_id()
  )
)
with check (
  exists (
    select 1
      from public.users
     where users.idx = users_quotes.user_idx
       and users.device_id = public.request_installation_id()
  )
);

create policy users_quotes_delete_own
on public.users_quotes for delete
to anon, authenticated
using (
  exists (
    select 1
      from public.users
     where users.idx = users_quotes.user_idx
       and users.device_id = public.request_installation_id()
  )
);

create policy quotes_public_read
on public.quotes for select
to anon, authenticated
using (true);

create policy device_shares_select_own
on public.device_shares for select
to anon, authenticated
using (device_id = public.request_installation_id());

create policy device_shares_insert_own
on public.device_shares for insert
to anon, authenticated
with check (device_id = public.request_installation_id());

create policy device_shares_update_own
on public.device_shares for update
to anon, authenticated
using (device_id = public.request_installation_id())
with check (device_id = public.request_installation_id());

create policy request_quotes_select_own
on public.request_quotes for select
to anon, authenticated
using (device_id = public.request_installation_id());

create policy request_quotes_insert_own
on public.request_quotes for insert
to anon, authenticated
with check (
  device_id = public.request_installation_id()
  and is_accept is null
  and length(trim(text_kr)) between 1 and 1000
  and length(trim(resoner_kr)) between 1 and 200
  and length(trim(tag_kr)) between 1 and 100
);

create policy request_quote_images_read_own_or_published
on public.request_quote_images for select
to anon, authenticated
using (
  exists (
    select 1
      from public.quotes
     where quotes.id = 'req_' || request_quote_images.request_quote_idx::text
  )
  or exists (
    select 1
      from public.request_quotes
     where request_quotes.id = request_quote_images.request_quote_idx
       and request_quotes.device_id = public.request_installation_id()
  )
);

create policy request_quote_images_insert_own
on public.request_quote_images for insert
to anon, authenticated
with check (
  exists (
    select 1
      from public.request_quotes
     where request_quotes.id = request_quote_images.request_quote_idx
       and request_quotes.device_id = public.request_installation_id()
  )
  and image_url like (
    '%/avatars/quote_requests/'
    || public.request_installation_id()
    || '/%'
  )
);

revoke all on table public.users from anon, authenticated;
revoke all on table public.users_quotes from anon, authenticated;
revoke all on table public.quotes from anon, authenticated;
revoke all on table public.device_shares from anon, authenticated;
revoke all on table public.request_quotes from anon, authenticated;
revoke all on table public.request_quote_images from anon, authenticated;

grant select, insert, update on table public.users to anon, authenticated;
grant select, insert, update, delete on table public.users_quotes
  to anon, authenticated;
grant select on table public.quotes to anon, authenticated;
grant select, insert, update on table public.device_shares
  to anon, authenticated;
grant select (id), insert (text_kr, resoner_kr, tag_kr, device_id)
  on public.request_quotes to anon, authenticated;
grant select, insert (request_quote_idx, image_url)
  on public.request_quote_images to anon, authenticated;

grant usage, select on sequence public.users_idx_seq to anon, authenticated;
grant usage, select on sequence public.request_quote_images_id_seq
  to anon, authenticated;

drop policy if exists "Anyone can view avatars" on storage.objects;
drop policy if exists "Anyone can upload avatars" on storage.objects;
drop policy if exists "Anyone can update avatars" on storage.objects;

update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array[
         'image/jpeg',
         'image/png',
         'image/webp',
         'image/heic',
         'image/heif'
       ]
 where id = 'avatars';

create policy avatars_select_own_uploads
on storage.objects for select
to anon, authenticated
using (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'profiles'
      and split_part(storage.filename(name), '.', 1)
        = public.request_installation_id()
    )
    or (
      (storage.foldername(name))[1] = 'quote_requests'
      and (storage.foldername(name))[2]
        = public.request_installation_id()
    )
  )
);

create policy avatars_insert_own_uploads
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'avatars'
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp', 'heic', 'heif')
  and (
    (
      (storage.foldername(name))[1] = 'profiles'
      and split_part(storage.filename(name), '.', 1)
        = public.request_installation_id()
    )
    or (
      (storage.foldername(name))[1] = 'quote_requests'
      and (storage.foldername(name))[2]
        = public.request_installation_id()
    )
  )
);

create policy avatars_update_own_uploads
on storage.objects for update
to anon, authenticated
using (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'profiles'
      and split_part(storage.filename(name), '.', 1)
        = public.request_installation_id()
    )
    or (
      (storage.foldername(name))[1] = 'quote_requests'
      and (storage.foldername(name))[2]
        = public.request_installation_id()
    )
  )
)
with check (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'profiles'
      and split_part(storage.filename(name), '.', 1)
        = public.request_installation_id()
    )
    or (
      (storage.foldername(name))[1] = 'quote_requests'
      and (storage.foldername(name))[2]
        = public.request_installation_id()
    )
  )
);
