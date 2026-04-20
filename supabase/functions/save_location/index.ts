// Supabase Edge Function: save_location
// Updates the driver's current location

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface SaveLocationRequest {
  driver_id: string;
  lat: number;
  lng: number;
  heading?: number;
  speed?: number;
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

    const body: SaveLocationRequest = await req.json();
    const { driver_id, lat, lng, heading, speed } = body;

    if (!driver_id || lat === undefined || lng === undefined) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update driver location using raw SQL to properly set the PostGIS geography column
    // We use a raw query via Supabase's rpc to handle the geography type
    const { error: updateError } = await supabaseClient.rpc('update_driver_location', {
      p_driver_id: driver_id,
      p_lat: lat,
      p_lng: lng,
      p_heading: heading ?? 0,
      p_speed: speed ?? 0,
    });

    // Fallback to simple upsert if RPC doesn't exist (location won't have geography)
    if (updateError && updateError.code === '42883') { // function does not exist
      const { error: fallbackError } = await supabaseClient
        .from('driver_locations')
        .upsert({
          driver_id: driver_id,
          lat: lat,
          lng: lng,
          heading: heading ?? 0,
          speed: speed ?? 0,
          updated_at: new Date().toISOString(),
        })
        .select();

      if (fallbackError) {
        console.error('Error updating location:', fallbackError);
        return new Response(
          JSON.stringify({ error: 'Failed to update location' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    } else if (updateError) {
      console.error('Error updating location:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to update location' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true }),
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
