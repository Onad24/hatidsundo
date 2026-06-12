import { createClient } from "npm:@supabase/supabase-js";

const supabaseUrl = process.env.SUPABASE_URL || "https://dwogrvalyrbubwsaunyo.supabase.co";
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(supabaseUrl, supabaseKey);

async function run() {
  const { data, error } = await supabase
    .from("trips")
    .select("id, status, vehicle_type, fare_estimated, fare_final, distance_km, driver_pickup_distance_km, created_at")
    .order("created_at", { ascending: false })
    .limit(5);

  if (error) console.error(error);
  else console.log(JSON.stringify(data, null, 2));
}
run();
