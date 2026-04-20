-- 1. Enable RLS
alter table driver_locations enable row level security;

-- 2. Clean up ANY existing policies (important to avoid conflicts)
drop policy if exists "Drivers can manage own location" on driver_locations;
drop policy if exists "Users can view online drivers" on driver_locations;
drop policy if exists "Enable insert for drivers" on driver_locations;
drop policy if exists "Enable select for users" on driver_locations;

-- 3. Policy: Drivers can INSERT/UPDATE their own location
-- Using 'driver_id' based on the Dart model inspection
create policy "Drivers can manage own location"
on driver_locations
for all
to authenticated
using ( driver_id = auth.uid() )
with check ( driver_id = auth.uid() );

-- 4. Policy: EVERYONE (Drivers + Clients) can VIEW active drivers
create policy "Users can view online drivers"
on driver_locations
for select
to authenticated
using ( true );

-- 5. Debug Policy (Optional) - If the above fails, uncomment this to allow ALL authenticated actions for testing:
-- create policy "DEBUG: Allow All Authenticated" on driver_locations for all to authenticated using (true);
