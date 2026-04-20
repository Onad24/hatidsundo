-- Migration: Add update_driver_location function for PostGIS support
-- Run this after 001_initial_schema.sql

-- Function to update driver location with proper PostGIS geography
CREATE OR REPLACE FUNCTION update_driver_location(
    p_driver_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_heading DOUBLE PRECISION DEFAULT 0,
    p_speed DOUBLE PRECISION DEFAULT 0
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO driver_locations (driver_id, lat, lng, location, heading, speed, updated_at)
    VALUES (
        p_driver_id,
        p_lat,
        p_lng,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        p_heading,
        p_speed,
        NOW()
    )
    ON CONFLICT (driver_id) DO UPDATE SET
        lat = EXCLUDED.lat,
        lng = EXCLUDED.lng,
        location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        heading = EXCLUDED.heading,
        speed = EXCLUDED.speed,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;
