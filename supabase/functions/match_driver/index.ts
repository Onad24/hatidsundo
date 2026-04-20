// Supabase Edge Function: match_driver
// Finds and assigns the nearest available driver to a trip

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

    // Get the closest driver
    const closestDriver = drivers[0];

    // Check if driver has outstanding dues
    const { data: hasOutstanding } = await supabaseClient
      .rpc('has_outstanding_dues', { p_rider_id: closestDriver.driver_id });

    if (hasOutstanding) {
      // Skip this driver and try the next one
      const availableDriver = drivers.find(async (d: any) => {
        const { data } = await supabaseClient
          .rpc('has_outstanding_dues', { p_rider_id: d.driver_id });
        return !data;
      });

      if (!availableDriver) {
        return new Response(
          JSON.stringify({ 
            matched: false, 
            message: 'No eligible drivers available' 
          }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Update trip with assigned driver
    const { error: updateError } = await supabaseClient
      .from('trips')
      .update({
        rider_id: closestDriver.driver_id,
        status: 'accepted',
        accepted_at: new Date().toISOString(),
        driver_pickup_distance_km: closestDriver.distance_km,
      })
      .eq('id', trip_id)
      .eq('status', 'pending');

    if (updateError) {
      console.error('Error updating trip:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to assign driver' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Mark driver as unavailable
    await supabaseClient
      .from('driver_locations')
      .update({
        is_available: false,
        current_trip_id: trip_id,
      })
      .eq('driver_id', closestDriver.driver_id);

    // Get driver info
    const { data: driverInfo } = await supabaseClient
      .from('users')
      .select('id, name, phone, avatar_url')
      .eq('id', closestDriver.driver_id)
      .single();

    const { data: riderProfile } = await supabaseClient
      .from('rider_profiles')
      .select('vehicle_type, vehicle_make, vehicle_model, vehicle_color, plate_number, rating')
      .eq('user_id', closestDriver.driver_id)
      .single();

    // Send push notification to driver
    const { data: driverUser } = await supabaseClient
      .from('users')
      .select('fcm_token')
      .eq('id', closestDriver.driver_id)
      .single();

    if (driverUser?.fcm_token) {
      // TODO: Send FCM notification
      console.log('Would send FCM to:', driverUser.fcm_token);
    }

    // Create notification for driver
    await supabaseClient.from('notifications').insert({
      user_id: closestDriver.driver_id,
      type: 'ride_request',
      title: 'New Ride Request',
      body: 'You have been assigned a new ride.',
      payload: { trip_id },
    });

    // Get client info for notification
    const { data: trip } = await supabaseClient
      .from('trips')
      .select('client_id')
      .eq('id', trip_id)
      .single();

    if (trip) {
      // Create notification for client
      await supabaseClient.from('notifications').insert({
        user_id: trip.client_id,
        type: 'driver_assigned',
        title: 'Driver Assigned',
        body: `${driverInfo?.name || 'A driver'} is on the way!`,
        payload: { 
          trip_id,
          driver_id: closestDriver.driver_id,
        },
      });
    }

    return new Response(
      JSON.stringify({
        matched: true,
        driver: {
          id: closestDriver.driver_id,
          ...driverInfo,
          ...riderProfile,
          distance_km: closestDriver.distance_km,
          eta_min: Math.ceil(closestDriver.distance_km * 2), // Rough ETA
        },
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
