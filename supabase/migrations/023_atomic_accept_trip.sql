-- Migration: Create atomic accept_trip RPC to prevent race conditions
-- When multiple riders try to accept the same pending trip simultaneously,
-- only one should succeed. This uses SELECT ... FOR UPDATE to lock the row.

CREATE OR REPLACE FUNCTION accept_trip_rpc(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trip RECORD;
  v_result JSON;
BEGIN
  -- Lock the trip row and verify it's still pending with no rider
  SELECT * INTO v_trip
  FROM trips
  WHERE id = p_trip_id
    AND status = 'pending'
    AND rider_id IS NULL
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Trip is no longer available (already accepted or cancelled)';
  END IF;

  -- Verify the caller is an approved rider
  IF NOT EXISTS (
    SELECT 1 FROM rider_profiles
    WHERE user_id = auth.uid()
    AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Only approved riders can accept trips';
  END IF;

  -- Atomically assign the rider and update status
  UPDATE trips
  SET
    rider_id = auth.uid(),
    status = 'accepted',
    accepted_at = NOW()
  WHERE id = p_trip_id
  RETURNING row_to_json(trips.*) INTO v_result;

  -- Mark driver as unavailable
  UPDATE driver_locations
  SET is_available = false, current_trip_id = p_trip_id
  WHERE driver_id = auth.uid();

  RETURN v_result;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION accept_trip_rpc TO authenticated;
