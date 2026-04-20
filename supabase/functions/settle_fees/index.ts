// Supabase Edge Function: settle_fees
// Admin function to settle rider fees

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface SettleFeesRequest {
  rider_id: string;
  amount: number;
  admin_id: string;
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

    const body: SettleFeesRequest = await req.json();
    const { rider_id, amount, admin_id, notes } = body;

    if (!rider_id || !amount || !admin_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Verify admin
    const { data: admin } = await supabaseClient
      .from('users')
      .select('role')
      .eq('id', admin_id)
      .single();

    if (!admin || admin.role !== 'admin') {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get unsettled fees for the rider
    const { data: unsettledFees, error: feesError } = await supabaseClient
      .from('monthly_fees')
      .select('*')
      .eq('rider_id', rider_id)
      .eq('is_settled', false)
      .order('year', { ascending: true })
      .order('month', { ascending: true });

    if (feesError) {
      return new Response(
        JSON.stringify({ error: 'Failed to get fees' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!unsettledFees || unsettledFees.length === 0) {
      return new Response(
        JSON.stringify({ error: 'No unsettled fees found' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Calculate total outstanding
    let totalOutstanding = 0;
    for (const fee of unsettledFees) {
      totalOutstanding += (fee.accrued_fee + fee.due_amount - fee.paid_amount);
    }

    if (amount > totalOutstanding) {
      return new Response(
        JSON.stringify({ 
          error: 'Payment amount exceeds outstanding balance',
          outstanding: totalOutstanding,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Apply payment to fees (oldest first)
    let remainingAmount = amount;
    const settledFees: string[] = [];
    const partiallyPaidFees: string[] = [];

    for (const fee of unsettledFees) {
      if (remainingAmount <= 0) break;

      const feeOutstanding = fee.accrued_fee + fee.due_amount - fee.paid_amount;
      const paymentToApply = Math.min(remainingAmount, feeOutstanding);

      const newPaidAmount = fee.paid_amount + paymentToApply;
      const isFullyPaid = newPaidAmount >= (fee.accrued_fee + fee.due_amount);

      await supabaseClient
        .from('monthly_fees')
        .update({
          paid_amount: newPaidAmount,
          is_settled: isFullyPaid,
          settled_at: isFullyPaid ? new Date().toISOString() : null,
          settled_by: isFullyPaid ? admin_id : null,
        })
        .eq('id', fee.id);

      if (isFullyPaid) {
        settledFees.push(fee.id);
      } else {
        partiallyPaidFees.push(fee.id);
      }

      remainingAmount -= paymentToApply;
    }

    // Create fee event for the settlement
    await supabaseClient.from('fee_events').insert({
      rider_id,
      amount: -amount, // Negative because it's a payment
      event_type: 'settlement',
      description: notes || `Fee settlement of ₱${amount.toFixed(0)} by admin`,
      created_by: admin_id,
    });

    // Create notification for rider
    await supabaseClient.from('notifications').insert({
      user_id: rider_id,
      type: 'payment',
      title: 'Fee Settlement',
      body: `A payment of ₱${amount.toFixed(0)} has been applied to your account.`,
      payload: { amount, settled_fees: settledFees },
    });

    // Calculate new outstanding
    const { data: newOutstanding } = await supabaseClient
      .rpc('get_outstanding_fees', { p_rider_id: rider_id });

    return new Response(
      JSON.stringify({
        success: true,
        settled_amount: amount,
        settled_fees: settledFees.length,
        partially_paid_fees: partiallyPaidFees.length,
        remaining_outstanding: newOutstanding || 0,
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
