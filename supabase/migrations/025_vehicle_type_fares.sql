-- =============================================================================
-- Add vehicle type to trips + per-vehicle-type fare rates
-- =============================================================================

-- 1. Add vehicle_type to trips so clients can request a specific vehicle type
ALTER TABLE trips ADD COLUMN IF NOT EXISTS vehicle_type TEXT;

-- 2. Add per-vehicle-type fare rates to fare_settings
ALTER TABLE fare_settings
  ADD COLUMN IF NOT EXISTS base_fare_motorcycle DECIMAL(10, 2) NOT NULL DEFAULT 20.0,
  ADD COLUMN IF NOT EXISTS base_fare_sedan DECIMAL(10, 2) NOT NULL DEFAULT 25.0,
  ADD COLUMN IF NOT EXISTS base_fare_suv DECIMAL(10, 2) NOT NULL DEFAULT 35.0,
  ADD COLUMN IF NOT EXISTS per_km_rate_motorcycle DECIMAL(10, 2) NOT NULL DEFAULT 6.0,
  ADD COLUMN IF NOT EXISTS per_km_rate_sedan DECIMAL(10, 2) NOT NULL DEFAULT 8.0,
  ADD COLUMN IF NOT EXISTS per_km_rate_suv DECIMAL(10, 2) NOT NULL DEFAULT 12.0;

-- Seed the new columns from the existing values for backward compat
UPDATE fare_settings
SET base_fare_motorcycle = GREATEST(base_fare - 5, 15),
    base_fare_sedan = base_fare,
    base_fare_suv = base_fare + 10,
    per_km_rate_motorcycle = GREATEST(per_km_rate - 2, 5),
    per_km_rate_sedan = per_km_rate,
    per_km_rate_suv = per_km_rate + 4
WHERE id = 1;

-- 3. Update get_nearby_drivers to optionally filter by vehicle type
CREATE OR REPLACE FUNCTION get_nearby_drivers(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 5,
    p_vehicle_type TEXT DEFAULT NULL
)
RETURNS TABLE (
    driver_id UUID,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    distance_km DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        dl.driver_id,
        dl.lat,
        dl.lng,
        dl.heading,
        ST_Distance(
            dl.location::geography,
            ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
        ) / 1000 AS distance_km
    FROM driver_locations dl
    JOIN rider_profiles rp ON dl.driver_id = rp.user_id
    WHERE dl.is_online = true
      AND dl.is_available = true
      AND dl.current_trip_id IS NULL
      AND rp.status = 'approved'
      AND (p_vehicle_type IS NULL OR rp.vehicle_type = p_vehicle_type)
      AND ST_DWithin(
          dl.location::geography,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          p_radius_km * 1000
      )
    ORDER BY distance_km ASC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;

-- 4. Update get_pending_trips_nearby to optionally filter by vehicle type
-- (Riders only see trips matching their vehicle type, or trips with no type specified)
CREATE OR REPLACE FUNCTION get_pending_trips_nearby(
    driver_lat DOUBLE PRECISION,
    driver_lng DOUBLE PRECISION,
    radius_km DOUBLE PRECISION DEFAULT 10,
    p_driver_vehicle_type TEXT DEFAULT NULL
)
RETURNS SETOF trips AS $$
BEGIN
    RETURN QUERY
    SELECT t.*
    FROM trips t
    WHERE t.status = 'pending'
      AND (
          p_driver_vehicle_type IS NULL
          OR t.vehicle_type IS NULL
          OR t.vehicle_type = p_driver_vehicle_type
      )
      AND ST_DWithin(
          t.pickup_location::geography,
          ST_SetSRID(ST_MakePoint(driver_lng, driver_lat), 4326)::geography,
          radius_km * 1000
      )
    ORDER BY t.created_at DESC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;
