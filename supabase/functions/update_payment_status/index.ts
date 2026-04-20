// Supabase Edge Function: update_payment_status
// Updates the payment status of a trip

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface UpdatePaymentRequest {
  trip_id: string;
  payment_status: 'pending' | 'completed' | 'failed';
  payment_method?: 'cash' | 'wallet';
  notes?: string;
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

    const body: UpdatePaymentRequest = await req.json();
    const { trip_id, payment_status, payment_method, notes } = body;

    if (!trip_id || !payment_status) {
      return new Response(
        JSON.stringify({ error: 'Missing trip_id or payment_status' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Update trip
    const { data: trip, error: updateError } = await supabaseClient
      .from('trips')
      .update({
        payment_status: payment_status,
        payment_method: payment_method || 'cash', // Default to cash if not provided
      })
      .eq('id', trip_id)
      .select()
      .single();

    if (updateError || !trip) {
      console.error('Error updating payment:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to update payment status' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Log fee event if payment completed
    if (payment_status === 'completed' && trip.rider_id) {
      // Add platform fee to rider's accrued fees
      const platformFee = trip.platform_fee || (trip.fare_final * 0.10);
      
      await supabaseClient.from('fee_events').insert({
        rider_id: trip.rider_id,
        trip_id: trip_id,
        amount: platformFee,
        event_type: 'trip_fee',
        description: `Platform fee for trip ${trip_id.substring(0,8)}`,
      });
    }

    // Notify parties
    // ...

    return new Response(
      JSON.stringify({ success: true, trip }),
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
