// Supabase Edge Function: start_trip
// Starts a trip and updates status to in_progress

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface StartTripRequest {
  trip_id: string;
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

    const body: StartTripRequest = await req.json();
    const { trip_id } = body;

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

    if (trip.status !== 'accepted' && trip.status !== 'arrived') {
       // Allow starting if accepted or arrived
       // If already in_progress, maybe return success idempotently?
       if (trip.status === 'in_progress') {
         return new Response(
            JSON.stringify({ success: true, trip }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
         );
       }
       
      return new Response(
        JSON.stringify({ error: `Cannot start trip with status: ${trip.status}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update trip values
    const { data: updatedTrip, error: updateError } = await supabaseClient
      .from('trips')
      .update({
        status: 'in_progress',
        started_at: new Date().toISOString(),
      })
      .eq('id', trip_id)
      .select()
      .single();

    if (updateError) {
      console.error('Error starting trip:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to start trip' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update driver status to avoid new matches?
    // Driver is already 'busy' if they have a trip?
    // Usually driver_locations.is_available is set to false when trip is accepted.
    // Ensure it is false.
     await supabaseClient
      .from('driver_locations')
      .update({
        is_available: false,
        current_trip_id: trip_id
      })
      .eq('driver_id', trip.rider_id);


    // Notify passenger
    await supabaseClient.from('notifications').insert([
      {
        user_id: trip.client_id,
        type: 'trip_started',
        title: 'Trip Started',
        body: 'Your trip has started! Enjoy the ride.',
        payload: { trip_id },
      },
    ]);

    return new Response(
      JSON.stringify({
        success: true,
        trip: updatedTrip,
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
