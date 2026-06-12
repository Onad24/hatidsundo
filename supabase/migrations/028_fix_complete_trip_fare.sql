-- Fix complete_trip_rpc to use fare_estimated as the base for fare_final
-- This ensures the final fare matches the estimated fare (which includes vehicle type and multipliers)

ALTER TABLE trips ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';

CREATE OR REPLACE FUNCTION complete_trip_rpc(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trip RECORD;
  v_fare DECIMAL(10, 2);
  v_result JSON;
BEGIN
  -- Get the trip details
  SELECT * INTO v_trip
  FROM trips
  WHERE id = p_trip_id
    AND rider_id = auth.uid()
    AND status = 'in_progress';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trip not found or not in progress for this rider';
  END IF;

  -- Calculate final fare:
  -- Base it on the estimated fare (which already calculated the distance)
  -- Just add the driver pickup distance fee (₱8 per km, floored)
  v_fare := v_trip.fare_estimated 
    + (FLOOR(COALESCE(v_trip.driver_pickup_distance_km, 0)) * 8);

  -- Complete the trip with recalculated fare
  UPDATE trips
  SET
    status = 'completed',
    completed_at = NOW(),
    fare_final = v_fare,
    payment_status = CASE 
      WHEN payment_method = 'cash' THEN 'pending'
      ELSE 'completed'
    END
  WHERE id = p_trip_id
  RETURNING row_to_json(trips.*) INTO v_result;

  RETURN v_result;
END;
$$;
