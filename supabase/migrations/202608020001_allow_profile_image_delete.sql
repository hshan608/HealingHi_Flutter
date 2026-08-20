drop policy if exists avatars_delete_own_profile on storage.objects;

create policy avatars_delete_own_profile
on storage.objects for delete
to anon, authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = 'profiles'
  and split_part(storage.filename(name), '.', 1)
    = public.request_installation_id()
);
