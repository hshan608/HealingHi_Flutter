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

revoke all on function public.admin_get_pending_quotes(text) from public;
grant execute on function public.admin_get_pending_quotes(text)
  to anon, authenticated;

notify pgrst, 'reload schema';
