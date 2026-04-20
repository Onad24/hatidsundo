# Supabase Storage Troubleshooting

You are encountering **502 Bad Gateway** and **403 Unauthorized** errors. These
indicate the server is rejecting the request or the bucket layout is incorrect.

## 1. Verify Bucket Exists

1. Go to your **Supabase Dashboard**.
2. Click on **Storage** in the left sidebar.
3. Look for a bucket named exactly: `driver_documents`.
   - **If it is missing**: Click "New Bucket", name it `driver_documents`, and
     ensure **"Public bucket" is CHECKED**.
   - **If it exists**: Click on the three dots `...` > `Edit Bucket` and ensure
     it is **Public**.

## 2. Verify Policies

Even if the bucket is public, Row Level Security (RLS) can block uploads.

1. Go to **SQL Editor**.
2. Run the following command to check if policies exist:
   ```sql
   select * from pg_policies where table_name = 'objects';
   ```
3. If you see no policies for `driver_documents`, runs the `policy_debug.sql`
   script I provided earlier.

## 3. Verify File Size

- Ensure the photos you are uploading are not huge (e.g. > 6MB). Supabase has a
  default limit (often 6MB or 50MB depending on plan).
- Try uploading a small test image.

## 4. Check Logs

- Go to **Database** > **Logs** in Supabase to see why the request is failing
  (500 error). It might show "relation does not exist" or "policy violation".
