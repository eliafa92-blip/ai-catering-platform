-- Storage for dish photos. The bucket is public, so anyone can view images by URL;
-- only the business owner can upload, replace or delete them.
-- dishes.image_path stores the object path inside this bucket, e.g. "dishes/<dish id>.png".

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dish-images', 'dish-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Upsert (replacing a file) needs insert + select + update.
create policy "Owner can list dish images" on storage.objects
  for select to authenticated
  using (bucket_id = 'dish-images' and (select private.is_owner()));

create policy "Owner can upload dish images" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'dish-images' and (select private.is_owner()));

create policy "Owner can replace dish images" on storage.objects
  for update to authenticated
  using (bucket_id = 'dish-images' and (select private.is_owner()))
  with check (bucket_id = 'dish-images' and (select private.is_owner()));

create policy "Owner can delete dish images" on storage.objects
  for delete to authenticated
  using (bucket_id = 'dish-images' and (select private.is_owner()));
