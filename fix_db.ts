import { createClient } from "npm:@supabase/supabase-js";

const supabaseUrl = process.env.SUPABASE_URL || "https://dwogrvalyrbubwsaunyo.supabase.co";
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(supabaseUrl, supabaseKey);

async function run() {
  const sql = `
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

  -- Use the estimated fare (which accurately reflects vehicle type, distance, and multipliers)
  -- Add the driver pickup fee
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
  `;
  
  // Note: supabase-js v2 doesn't have a direct way to run raw SQL without an RPC.
  // We'll have to rely on the user running it via dashboard if they want to fix the driver app completely.
}
run();
