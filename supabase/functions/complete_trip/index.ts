// Supabase Edge Function: complete_trip
// Completes a trip and calculates final fare and platform fee

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

    // Calculate final fare
    // Formula: ₱25 base + floor(driver→pickup km) × ₱8 + floor(pickup→dest km) × ₱8
    const BASE_FARE = 25;
    const PER_KM_RATE = 8;

    const driverPickupKm = Math.floor(trip.driver_pickup_distance_km ?? 0);
    const destKm = Math.floor(trip.distance_km ?? 0);
    const finalFare = BASE_FARE + (driverPickupKm * PER_KM_RATE) + (destKm * PER_KM_RATE);
    const platformFee = finalFare * 0.10; // 10% platform fee

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

    // Create notifications
    await supabaseClient.from('notifications').insert([
      {
        user_id: trip.client_id,
        type: 'trip_completed',
        title: 'Trip Completed',
        body: `Your trip has been completed. Fare: ₱${finalFare.toFixed(0)}`,
        payload: { trip_id, fare: finalFare },
      },
      {
        user_id: trip.rider_id,
        type: 'trip_completed',
        title: 'Trip Completed',
        body: `Trip completed. Earnings: ₱${(finalFare - platformFee).toFixed(0)}`,
        payload: { trip_id, earnings: finalFare - platformFee },
      },
    ]);

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
