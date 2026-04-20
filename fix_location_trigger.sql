-- Create a function to update the 'location' column automatically
create or replace function public.update_driver_location_geom()
returns trigger as $$
begin
  -- Update the 'location' geography column using lat/lng
  -- 4326 is the SRID for WGS 84 (standard GPS lat/lng)
  NEW.location := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
  return NEW;
end;
$$ language plpgsql security definer;

-- Create the trigger
-- Validates BEFORE insert or update to satisfy NOT NULL constraints
drop trigger if exists sync_driver_location on driver_locations;
create trigger sync_driver_location
before insert or update on driver_locations
for each row
execute function public.update_driver_location_geom();
