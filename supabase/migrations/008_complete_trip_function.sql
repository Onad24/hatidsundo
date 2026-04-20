-- Migration: Create a SECURITY DEFINER function for completing trips
-- This bypasses RLS so riders can reliably complete their active trips

CREATE OR REPLACE FUNCTION complete_trip_rpc(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trip RECORD;
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

  -- Calculate final fare
  UPDATE trips
  SET
    status = 'completed',
    completed_at = NOW(),
    fare_final = COALESCE(fare_final, fare_estimated),
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

-- Also create functions for marking driver arriving and starting trip
-- to avoid similar RLS issues

CREATE OR REPLACE FUNCTION mark_driver_arriving_rpc(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  UPDATE trips
  SET status = 'driver_arriving'
  WHERE id = p_trip_id
    AND rider_id = auth.uid()
    AND status = 'accepted'
  RETURNING row_to_json(trips.*) INTO v_result;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Trip not found or not in accepted state for this rider';
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION start_trip_rpc(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  UPDATE trips
  SET status = 'in_progress', started_at = NOW()
  WHERE id = p_trip_id
    AND rider_id = auth.uid()
    AND status = 'driver_arriving'
  RETURNING row_to_json(trips.*) INTO v_result;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Trip not found or not in driver_arriving state for this rider';
  END IF;

  RETURN v_result;
END;
$$;
