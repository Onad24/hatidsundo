// Supabase Edge Function: match_driver
// Notifies all nearby available drivers about a new pending trip
// Drivers accept from their pending trips list (first-come-first-served)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface MatchDriverRequest {
  trip_id: string;
  pickup_lat: number;
  pickup_lng: number;
  radius_km?: number;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const body: MatchDriverRequest = await req.json();
    const { trip_id, pickup_lat, pickup_lng, radius_km = 5 } = body;

    if (!trip_id || !pickup_lat || !pickup_lng) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get nearby available drivers
    const { data: drivers, error: driversError } = await supabaseClient
      .rpc('get_nearby_drivers', {
        p_lat: pickup_lat,
        p_lng: pickup_lng,
        p_radius_km: radius_km,
      });

    if (driversError) {
      console.error('Error getting nearby drivers:', driversError);
      return new Response(
        JSON.stringify({ error: 'Failed to find drivers' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!drivers || drivers.length === 0) {
      return new Response(
        JSON.stringify({ 
          matched: false, 
          message: 'No drivers available nearby' 
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Notify ALL nearby drivers about the new ride request
    const notifiedDrivers: string[] = [];
    for (const driver of drivers) {
      try {
        // Skip drivers with outstanding dues
        const { data: hasOutstanding } = await supabaseClient
          .rpc('has_outstanding_dues', { p_rider_id: driver.driver_id });
        
        if (hasOutstanding) continue;

        await sendFcmNotification(
          supabaseClient,
          driver.driver_id,
          'New Ride Request',
          'A new ride request is available nearby. Tap to accept.',
          { type: 'ride_request', trip_id: trip_id }
        );
        notifiedDrivers.push(driver.driver_id);
      } catch (e) {
        console.error(`Failed to notify driver ${driver.driver_id}:`, e);
      }
    }

    console.log(`Notified ${notifiedDrivers.length} drivers about trip ${trip_id}`);

    return new Response(
      JSON.stringify({
        matched: false,
        notified_drivers: notifiedDrivers.length,
        message: `Notified ${notifiedDrivers.length} nearby drivers`,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
