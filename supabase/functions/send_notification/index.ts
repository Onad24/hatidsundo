// Supabase Edge Function: send_notification
// Sends FCM push notifications to users via their stored FCM tokens

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface SendNotificationRequest {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, string>;
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

    const body: SendNotificationRequest = await req.json();
    const { user_id, title, body: notifBody, data = {} } = body;

    if (!user_id || !title) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: user_id, title' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if the user is a Facebook Messenger user
    const { data: fbUser } = await supabaseClient
      .from('fb_users')
      .select('psid')
      .eq('user_id', user_id)
      .maybeSingle();

    if (fbUser && fbUser.psid) {
      // Send Facebook Messenger message instead of FCM
      const PAGE_ACCESS_TOKEN = Deno.env.get("FB_PAGE_ACCESS_TOKEN") ?? "";
      const GRAPH_API = "https://graph.facebook.com/v19.0";
      
      const payload = {
        recipient: { id: fbUser.psid },
        message: { text: `🔔 ${title}\n${notifBody}` }
      };

      const res = await fetch(`${GRAPH_API}/me/messages?access_token=${PAGE_ACCESS_TOKEN}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
         console.error("FB Messenger error:", await res.text());
      }

      return new Response(
        JSON.stringify({
          sent: res.ok,
          sent_count: res.ok ? 1 : 0,
          total_tokens: 1,
          platform: 'facebook_messenger'
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Fallback to regular FCM for mobile app users
    const result = await sendFcmNotification(supabaseClient, user_id, title, notifBody, data);

    return new Response(
      JSON.stringify({
        sent: result.sent,
        sent_count: result.sentCount,
        total_tokens: result.totalTokens,
        platform: 'fcm'
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
