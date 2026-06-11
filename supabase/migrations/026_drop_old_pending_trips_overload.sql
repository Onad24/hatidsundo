-- =============================================================================
-- Fix PGRST203: Drop the old 3-parameter overload of get_pending_trips_nearby
-- =============================================================================
-- Migration 025 used CREATE OR REPLACE with a different signature (4 params),
-- which created a second overload instead of replacing the original.
-- PostgREST cannot disambiguate between the two, causing PGRST203.

-- Drop the OLD 3-parameter version (from migration 004)
DROP FUNCTION IF EXISTS get_pending_trips_nearby(
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION
);

-- The 4-parameter version from migration 025 remains:
-- get_pending_trips_nearby(driver_lat, driver_lng, radius_km, p_driver_vehicle_type)

-- Grant execute permission on the remaining function
GRANT EXECUTE ON FUNCTION get_pending_trips_nearby(
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    DOUBLE PRECISION,
    TEXT
) TO authenticated;
