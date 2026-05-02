// Supabase Edge Function: complete_trip
// Completes a trip and calculates final fare and platform fee

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface CompleteTripRequest {
  trip_id: string;
  final_lat?: number;
  final_lng?: number;
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

    const body: CompleteTripRequest = await req.json();
    const { trip_id, final_lat, final_lng } = body;

    if (!trip_id) {
      return new Response(
        JSON.stringify({ error: 'Missing trip_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get trip details
    const { data: trip, error: tripError } = await supabaseClient
      .from('trips')
      .select('*')
      .eq('id', trip_id)
      .single();

    if (tripError || !trip) {
      return new Response(
        JSON.stringify({ error: 'Trip not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (trip.status !== 'in_progress') {
      return new Response(
        JSON.stringify({ error: 'Trip is not in progress' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Fetch fare settings from database (falls back to defaults)
    let BASE_FARE = 25;
    let PER_KM_RATE = 8;
    let NIGHT_RATE_MULTIPLIER = 1.2;
    let NIGHT_START_HOUR = 21;
    let NIGHT_END_HOUR = 5;
    let PLATFORM_FEE_PERCENT = 0.10;

    try {
      const { data: fareRow } = await supabaseClient
        .from('fare_settings')
        .select('*')
        .eq('id', 1)
        .single();

      if (fareRow) {
        BASE_FARE = fareRow.base_fare ?? 25;
        PER_KM_RATE = fareRow.per_km_rate ?? 8;
        NIGHT_RATE_MULTIPLIER = fareRow.night_rate_multiplier ?? 1.2;
        NIGHT_START_HOUR = fareRow.night_start_hour ?? 21;
        NIGHT_END_HOUR = fareRow.night_end_hour ?? 5;
        PLATFORM_FEE_PERCENT = fareRow.platform_fee_percent ?? 0.10;
      }
    } catch (e) {
      console.log('Could not fetch fare settings, using defaults:', e);
    }

    // Apply night rate if applicable
    const currentHour = new Date().getHours();
    const isNight = currentHour >= NIGHT_START_HOUR || currentHour < NIGHT_END_HOUR;
    const nightMultiplier = isNight ? NIGHT_RATE_MULTIPLIER : 1.0;

    const driverPickupKm = Math.floor(trip.driver_pickup_distance_km ?? 0);
    const destKm = Math.floor(trip.distance_km ?? 0);
    const finalFare = BASE_FARE + (driverPickupKm * PER_KM_RATE) + (destKm * PER_KM_RATE * nightMultiplier);
    const platformFee = finalFare * PLATFORM_FEE_PERCENT;

    // Update trip as completed
    const { error: updateError } = await supabaseClient
      .from('trips')
      .update({
        status: 'completed',
        fare_final: finalFare,
        platform_fee: platformFee,
        completed_at: new Date().toISOString(),
        payment_status: 'pending',
      })
      .eq('id', trip_id);

    if (updateError) {
      console.error('Error completing trip:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to complete trip' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Free up the driver
    await supabaseClient
      .from('driver_locations')
      .update({
        is_available: true,
        current_trip_id: null,
      })
      .eq('driver_id', trip.rider_id);

    // Update rider stats
    const { data: riderProfile } = await supabaseClient
      .from('rider_profiles')
      .select('total_trips')
      .eq('user_id', trip.rider_id)
      .single();
    
    if (riderProfile) {
      await supabaseClient
        .from('rider_profiles')
        .update({
          total_trips: (riderProfile.total_trips || 0) + 1,
        })
        .eq('user_id', trip.rider_id);
    }

    // Notify client via shared fcm module
    try {
      await sendFcmNotification(
        supabaseClient,
        trip.client_id,
        'Trip Completed',
        `Your trip has been completed. Fare: ₱${finalFare.toFixed(0)}`,
        { type: 'trip_completed', trip_id: trip_id, fare: finalFare.toString() }
      );
    } catch (e) {
      console.error('Failed to send trip completed notification to client:', e);
    }

    // Notify rider via shared fcm module
    try {
      await sendFcmNotification(
        supabaseClient,
        trip.rider_id,
        'Trip Completed',
        `Trip completed. Earnings: ₱${(finalFare - platformFee).toFixed(0)}`,
        { type: 'trip_completed', trip_id: trip_id, earnings: (finalFare - platformFee).toString() }
      );
    } catch (e) {
      console.error('Failed to send trip completed notification to rider:', e);
    }

    return new Response(
      JSON.stringify({
        success: true,
        trip: {
          id: trip_id,
          fare_final: finalFare,
          platform_fee: platformFee,
          driver_earnings: finalFare - platformFee,
          status: 'completed',
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
