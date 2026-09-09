-- Applied to Healing-HI via the Supabase Management API.
alter table public.device_shares
  add column if not exists quote_request_share_count integer not null default 0;

-- 기존 사용자는 현재 누적 공유 횟수를 신청용 첫 30회 진행도에 반영한다.
update public.device_shares
   set quote_request_share_count = least(greatest(share_count, 0), 30)
 where quote_request_share_count = 0;

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

  insert into public.device_shares (
    device_id,
    share_count,
    quote_request_share_count
  )
  values (v_installation_id, 1, 1)
  on conflict (device_id)
  do update set
    share_count = public.device_shares.share_count + 1,
    quote_request_share_count =
      public.device_shares.quote_request_share_count + 1,
    updated_at = now();
end;
$$;

revoke all on function public.increment_share_count(text) from public;
grant execute on function public.increment_share_count(text)
  to anon, authenticated;

create or replace function public.submit_quote_request(
  p_text_kr text,
  p_resoner_kr text,
  p_tag_kr text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_installation_id text := public.request_installation_id();
  v_quote_request_share_count integer;
  v_request_quote_id bigint;
begin
  if v_installation_id is null then
    raise exception 'invalid installation identity';
  end if;

  if length(trim(coalesce(p_text_kr, ''))) not between 1 and 1000
    or length(trim(coalesce(p_resoner_kr, ''))) not between 1 and 200
    or length(trim(coalesce(p_tag_kr, ''))) not between 1 and 100
  then
    raise exception 'invalid quote request';
  end if;

  select quote_request_share_count
    into v_quote_request_share_count
    from public.device_shares
   where device_id = v_installation_id
   for update;

  if coalesce(v_quote_request_share_count, 0) < 30 then
    raise exception '30 shares are required to submit a quote request';
  end if;

  insert into public.request_quotes (
    text_kr,
    resoner_kr,
    tag_kr,
    device_id
  )
  values (
    trim(p_text_kr),
    trim(p_resoner_kr),
    trim(p_tag_kr),
    v_installation_id
  )
  returning id into v_request_quote_id;

  update public.device_shares
     set quote_request_share_count = 0,
         updated_at = now()
   where device_id = v_installation_id;

  return v_request_quote_id;
end;
$$;

revoke all on function public.submit_quote_request(text, text, text) from public;
grant execute on function public.submit_quote_request(text, text, text)
  to anon, authenticated;

-- All client submissions must pass through the atomic 30-share check above.
drop policy if exists request_quotes_insert_own on public.request_quotes;
