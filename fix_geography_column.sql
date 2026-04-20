-- The logic: 
-- Instead of the App trying to format "location", we make the Database generate it automatically.
-- This is the most efficient and "direct" way in Postgres.

-- 1. Drop the existing column (since it's failing anyway)
alter table driver_locations drop column if exists location;

-- 2. Add it back as a GENERATED column
-- It will automatically update whenever lat or lng changes.
alter table driver_locations add column location geography(POINT, 4326) 
generated always as (ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography) stored;

-- 3. Verify RLS is still correct
alter table driver_locations enable row level security;
drop policy if exists "Drivers can manage own location" on driver_locations;
create policy "Drivers can manage own location"
on driver_locations
for all
to authenticated
using ( driver_id = auth.uid() )
with check ( driver_id = auth.uid() );
