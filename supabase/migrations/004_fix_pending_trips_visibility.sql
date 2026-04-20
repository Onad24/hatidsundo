-- Migration: Fix pending trips visibility for riders
-- Issue: Riders cannot see pending trips because:
-- 1. The `get_pending_trips_nearby` function is missing
-- 2. RLS policy requires rider_id = auth.uid(), but pending trips have no rider_id yet

-- =============================================================================
-- STEP 1: Add RLS policy for riders to see pending trips
-- =============================================================================

-- Policy to allow approved riders to view pending trips (for accepting rides)
CREATE POLICY "Approved riders can view pending trips" ON trips
    FOR SELECT 
    USING (
        status = 'pending' 
        AND rider_id IS NULL
        AND EXISTS (
            SELECT 1 FROM rider_profiles 
            WHERE rider_profiles.user_id = auth.uid() 
            AND rider_profiles.status = 'approved'
        )
    );

-- =============================================================================
-- STEP 2: Create the get_pending_trips_nearby function
-- =============================================================================

CREATE OR REPLACE FUNCTION get_pending_trips_nearby(
    driver_lat DOUBLE PRECISION,
    driver_lng DOUBLE PRECISION,
    radius_km DOUBLE PRECISION DEFAULT 5
)
RETURNS SETOF trips AS $$
BEGIN
    RETURN QUERY
    SELECT t.*
    FROM trips t
    WHERE t.status = 'pending'
      AND t.rider_id IS NULL
      AND ST_DWithin(
          t.pickup_location::geography,
          ST_SetSRID(ST_MakePoint(driver_lng, driver_lat), 4326)::geography,
          radius_km * 1000
      )
    ORDER BY 
        ST_Distance(
            t.pickup_location::geography,
            ST_SetSRID(ST_MakePoint(driver_lng, driver_lat), 4326)::geography
        ) ASC
    LIMIT 20;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_pending_trips_nearby TO authenticated;
