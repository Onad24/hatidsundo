
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Verify user is admin
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing Authorization header");
    }

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );

    if (userError || !user) {
      throw new Error("Invalid user");
    }

    // Check if user has admin role
    const { data: userData, error: roleError } = await supabaseClient
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single();

    if (roleError || userData?.role !== "admin") {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Admin access required" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { action, payload } = await req.json();

    if (action === "get_dashboard_stats") {
      // 1. Get active trips count
      const { count: activeTripsCount } = await supabaseClient
        .from("trips")
        .select("*", { count: "exact", head: true })
        .in("status", ["pending", "accepted", "driver_arriving", "in_progress"]);

      // 2. Get active drivers count
      const { count: activeDriversCount } = await supabaseClient
        .from("driver_locations")
        .select("*", { count: "exact", head: true })
        .eq("is_online", true);

      // 3. Get total revenue (accrued fees)
      const { data: feeData } = await supabaseClient
        .from("monthly_fees")
        .select("accrued_fee, due_amount");
      
      let totalRevenue = 0;
      let totalOutstanding = 0;
      
      if (feeData) {
        feeData.forEach((row: any) => {
          totalRevenue += (row.accrued_fee || 0);
          totalOutstanding += (row.due_amount || 0);
        });
      }

      // 4. Get recent trips (last 24h)
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      
      const { count: recentTripsCount } = await supabaseClient
        .from("trips")
        .select("*", { count: "exact", head: true })
        .gte("created_at", yesterday.toISOString());

      return new Response(
        JSON.stringify({
          active_trips: activeTripsCount || 0,
          active_drivers: activeDriversCount || 0,
          total_revenue: totalRevenue,
          total_outstanding: totalOutstanding,
          recent_trips_24h: recentTripsCount || 0,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ error: "Invalid action" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );

  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
