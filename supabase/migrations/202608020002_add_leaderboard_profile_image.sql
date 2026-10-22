drop function if exists public.get_share_leaderboard();

create function public.get_share_leaderboard()
returns table (
  rank bigint,
  display_name text,
  profile_image_url text,
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
    u.profile_image_url::text,
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
