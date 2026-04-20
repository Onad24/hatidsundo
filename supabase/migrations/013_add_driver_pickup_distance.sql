-- Migration: Add driver_pickup_distance_km column to trips table
-- This stores the distance from the assigned driver to the pickup location,
-- which is used in the fare calculation:
--   fare = 25 + floor(driver_pickup_distance_km) * 8 + floor(distance_km) * 8

ALTER TABLE trips
  ADD COLUMN IF NOT EXISTS driver_pickup_distance_km DOUBLE PRECISION;

-- Update complete_trip_rpc to use the new fare formula
CREATE OR REPLACE FUNCTION complete_trip_rpc(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trip RECORD;
  v_fare NUMERIC;
  v_result JSON;
BEGIN
  -- Verify the trip exists and belongs to the calling user (as rider)
  SELECT * INTO v_trip
  FROM trips
  WHERE id = p_trip_id
    AND rider_id = auth.uid()
    AND status = 'in_progress';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trip not found or not in progress for this rider';
  END IF;

  -- Calculate final fare:
  -- ₱25 base + floor(driver→pickup km) × ₱8 + floor(pickup→dest km) × ₱8
  v_fare := 25
    + (FLOOR(COALESCE(v_trip.driver_pickup_distance_km, 0)) * 8)
    + (FLOOR(COALESCE(v_trip.distance_km, 0)) * 8);

  -- Complete the trip with recalculated fare
  UPDATE trips
  SET
    status = 'completed',
    completed_at = NOW(),
    fare_final = v_fare,
    payment_status = 'pending'
  WHERE id = p_trip_id
  RETURNING row_to_json(trips.*) INTO v_result;

  -- Free up the driver
  UPDATE driver_locations
  SET is_available = true, current_trip_id = NULL
  WHERE driver_id = auth.uid();

  RETURN v_result;
END;
$$;
