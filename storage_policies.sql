-- Enable RLS on storage.objects (if not already enabled)
alter table storage.objects enable row level security;

-- Policy to allow authenticated users to upload files to their own folder in 'driver_documents'
create policy "Allow Authenticated Uploads"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'driver_documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy to allow users to view/download their own files
create policy "Allow Users to View Own Files"
on storage.objects for select
to authenticated
using (
  bucket_id = 'driver_documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy to allow users to update/delete their own files (optional, but good for retries)
create policy "Allow Users to Update Own Files"
on storage.objects for update
to authenticated
using (
  bucket_id = 'driver_documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- NOTE: If your bucket is public, 'getPublicUrl' works. 
-- If it's private, you might need to create a Signed URL instead or set the bucket to Public.
-- To make the bucket public (if desired):
-- insert into storage.buckets (id, name, public) values ('driver_documents', 'driver_documents', true);
