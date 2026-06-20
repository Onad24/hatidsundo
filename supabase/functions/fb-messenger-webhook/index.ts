/**
 * Hatid Sundo — Facebook Messenger Webhook
 * =========================================
 * Full client-side bot with:
 *  - Multi-step ride booking (conversational, with location pins)
 *  - Live ride status from Supabase
 *  - Ride cancellation
 *  - Driver ↔ client message relay via the messages table
 *  - Human agent handover via Facebook Handover Protocol
 *  - Session state persistence in bot_sessions table
 *  - PSID → user mapping in fb_users table
 *
 * Required environment variables (set in Supabase Dashboard → Edge Functions → Secrets):
 *   FB_VERIFY_TOKEN          — your chosen webhook verification token
 *   FB_PAGE_ACCESS_TOKEN     — your Facebook Page access token
 *   FB_APP_ID                — your Facebook App ID (for Handover Protocol)
 *   SUPABASE_URL             — your Supabase project URL
 *   SUPABASE_SERVICE_ROLE_KEY — service role key (bypasses RLS)
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// ENV
// ---------------------------------------------------------------------------
const FB_VERIFY_TOKEN = Deno.env.get("FB_VERIFY_TOKEN") ?? "my_verify_token";
const PAGE_ACCESS_TOKEN = Deno.env.get("FB_PAGE_ACCESS_TOKEN") ?? "";
const FB_APP_ID = Deno.env.get("FB_APP_ID") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PRIVACY_POLICY_URL = Deno.env.get("PRIVACY_POLICY_URL") ?? "https://your-site.com/privacy.html";

// Graph API base URL
const GRAPH_API = "https://graph.facebook.com/v19.0";

// Supabase client with service role — bypasses RLS, safe for server-only use
function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

// ---------------------------------------------------------------------------
// SESSION STATE MACHINE
// ---------------------------------------------------------------------------
type SessionState =
  | "idle"
  | "awaiting_pickup"
  | "awaiting_destination"
  | "awaiting_vehicle"
  | "awaiting_confirm"
  | "handover";

interface SessionData {
  pickup_lat?: number;
  pickup_lng?: number;
  pickup_addr?: string;
  dest_lat?: number;
  dest_lng?: number;
  dest_addr?: string;
  vehicle_type?: string;
}

interface BotSession {
  psid: string;
  state: SessionState;
  data: SessionData;
}

// ---------------------------------------------------------------------------
// TYPES
// ---------------------------------------------------------------------------
interface FbProfile {
  first_name?: string;
  last_name?: string;
  name?: string;
  profile_pic?: string;
}

interface TripRow {
  id: string;
  status: string;
  pickup_address?: string;
  dest_address?: string;
  fare_estimated: number;
  fare_final?: number;
  vehicle_type?: string;
  distance_km?: number;
  duration_min?: number;
  rider_id?: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ---------------------------------------------------------------------------
// WEBVIEW MAP SUBMISSION (Leaflet & OpenStreetMap)
// ---------------------------------------------------------------------------

async function handleSubmitLocation(req: Request): Promise<Response> {
  try {
    const body = await req.json();
    const { psid, pickup_lat, pickup_lng, pickup_addr, dest_lat, dest_lng, dest_addr } = body;

    if (!psid) {
      return new Response("Missing psid", { status: 400, headers: corsHeaders });
    }

    // Resolve addresses via reverse-geocode if not supplied by the map page
    const resolvedPickupAddr = pickup_addr || await reverseGeocode(pickup_lat, pickup_lng);
    const resolvedDestAddr   = dest_addr   || await reverseGeocode(dest_lat, dest_lng);

    const data: SessionData = {
      pickup_lat,
      pickup_lng,
      pickup_addr: resolvedPickupAddr,
      dest_lat,
      dest_lng,
      dest_addr: resolvedDestAddr,
    };

    // Jump straight to vehicle selection — no second map needed
    await setSession(psid, "awaiting_vehicle", data);
    await askVehicleType(psid);

    return new Response("OK", { status: 200, headers: corsHeaders });
  } catch (err) {
    console.error("Location submission error:", err);
    return new Response("Internal Server Error", { status: 500, headers: corsHeaders });
  }
}

// ---------------------------------------------------------------------------
// MAIN SERVER
// ---------------------------------------------------------------------------
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  // ── Webhook Verification (GET) ──────────────────────────────────────────
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");

    if (mode === "subscribe" && token === FB_VERIFY_TOKEN) {
      console.log("WEBHOOK_VERIFIED");
      return new Response(challenge, { status: 200 });
    }
    return new Response("Forbidden", { status: 403 });
  }

  // ── Webhook Events & Map Post (POST) ──────────────────────────────────
  if (req.method === "POST") {
    if (action === "submit_location") return handleSubmitLocation(req);

    try {
      const body = await req.json();

      if (body.object === "page") {
        await Promise.all(
          body.entry.map(async (entry: any) => {
            const events: any[] = [...(entry.messaging || []), ...(entry.standby || [])];
            for (const event of events) {
              await dispatchEvent(event);
            }
          })
        );
        return new Response("EVENT_RECEIVED", { status: 200 });
      }
      return new Response("Not Found", { status: 404 });
    } catch (err) {
      console.error("Error processing webhook event:", err);
      return new Response("Internal Server Error", { status: 500 });
    }
  }

  return new Response("Method not allowed", { status: 405 });
});

// ---------------------------------------------------------------------------
// EVENT DISPATCHER
// ---------------------------------------------------------------------------
async function dispatchEvent(event: any) {
  const psid: string = event.sender.id;

  // Echo back — ignore our own messages to avoid loops
  if (event.message?.is_echo) return;

  // Ensure user exists in fb_users (upsert)
  await getOrCreateFbUser(psid);

  if (event.message) {
    await handleMessage(psid, event.message);
  } else if (event.postback) {
    await handlePostback(psid, event.postback);
  }
}

// ---------------------------------------------------------------------------
// MESSAGE HANDLER
// ---------------------------------------------------------------------------
async function handleMessage(psid: string, message: any) {
  const session = await getSession(psid);

  // ── Attachments (e.g. location pins) ────────────────────────────────────
  if (message.attachments) {
    for (const att of message.attachments) {
      if (att.type === "location") {
        await handleLocationAttachment(psid, session, att.payload.coordinates);
        return;
      }
    }
    // Non-location attachment during idle — just show menu
    if (session.state === "idle") {
      await sendMainMenu(psid, "I see you shared something! Here's what I can help with:");
      return;
    }
  }

  const text: string = (message.text ?? "").trim();
  if (!text) return;

  const lower = text.toLowerCase();

  // ── State machine: route to active flow if mid-booking ──────────────────
  switch (session.state) {
    case "awaiting_pickup":
      await handlePickupText(psid, session, text);
      return;
    case "awaiting_destination":
      await handleDestinationText(psid, session, text);
      return;
    case "awaiting_vehicle":
      await handleVehicleChoice(psid, session, text);
      return;
    case "awaiting_confirm":
      await handleConfirmChoice(psid, session, lower);
      return;
    case "handover":
      // If user types a known keyword, pull thread control back to the bot
      if (
        lower === "book a ride" ||
        lower === "check my ride" ||
        lower === "message driver" ||
        lower === "main menu" ||
        lower === "cancel request" ||
        lower === "exit"
      ) {
        await takeThreadControlBack(psid);
        await clearSession(psid);
        if (lower === "book a ride") {
          await startBookingFlow(psid);
        } else if (lower === "check my ride") {
          await checkStatus(psid);
        } else if (lower === "cancel request") {
          await initiateCancelRide(psid);
        } else if (lower === "message driver") {
          await promptDriverMessage(psid);
        } else {
          await sendMainMenu(psid);
        }
      } else if (lower === "cancel") {
        const trip = await getActiveTrip(psid);
        if (trip && (trip.status === "pending" || trip.status === "offered")) {
          await takeThreadControlBack(psid);
          await clearSession(psid);
          await initiateCancelRide(psid);
        }
      }
      return;
  }

  // ── Idle intent matching ─────────────────────────────────────────────────
  if (lower === "book a ride") {
    await startBookingFlow(psid);
  } else if (lower === "check my ride") {
    await checkStatus(psid);
  } else if (lower === "cancel request") {
    await initiateCancelRide(psid);
  } else if (lower === "message driver") {
    await promptDriverMessage(psid);
  } else if (lower === "talk to an agent") {
    await handleHumanHandover(psid);
  } else if (lower === "main menu" || lower === "exit") {
    await sendMainMenu(psid);
  } else if (lower === "cancel") {
    const trip = await getActiveTrip(psid);
    if (trip && (trip.status === "pending" || trip.status === "offered")) {
      await initiateCancelRide(psid);
    } else {
      if (trip) {
        await relayMessageToDriver(psid, trip, text);
      } else {
        await sendMainMenu(psid, "I didn't quite get that. Here's what I can do:");
      }
    }
  } else {
    // During active trip, treat unknown messages as driver messages
    const trip = await getActiveTrip(psid);
    if (trip) {
      await relayMessageToDriver(psid, trip, text);
    } else {
      await sendMainMenu(psid, "I didn't quite get that. Here's what I can do:");
    }
  }
}

// ---------------------------------------------------------------------------
// POSTBACK HANDLER (button taps)
// ---------------------------------------------------------------------------
async function handlePostback(psid: string, postback: any) {
  const payload: string = postback.payload;
  const session = await getSession(psid);

  // If user interacts with a bot button, always reclaim thread control (unless they are explicitly asking for a human)
  if (payload !== "TALK_TO_HUMAN") {
    await takeThreadControlBack(psid);
  }

  switch (payload) {
    case "GET_STARTED":
      await sendWelcomeMessage(psid);
      break;

    case "MAIN_MENU":
      await sendMainMenu(psid);
      break;

    case "BOOK_RIDE":
      await startBookingFlow(psid);
      break;

    case "CHECK_STATUS":
      await checkStatus(psid);
      break;

    case "CANCEL_RIDE":
      await initiateCancelRide(psid);
      break;

    case "CONFIRM_CANCEL":
      await executeCancelRide(psid);
      break;

    case "CONFIRM_BOOKING":
      await executeBooking(psid, session);
      break;

    case "ABORT_BOOKING":
      await clearSession(psid);
      await sendMessage(psid, { text: "No problem! Booking cancelled. What else can I help you with?" });
      await sendMainMenu(psid);
      break;

    case "TALK_TO_HUMAN":
      await handleHumanHandover(psid);
      break;

    case "VEHICLE_MOTORCYCLE":
      await handleVehicleChoice(psid, session, "motorcycle");
      break;

    case "VEHICLE_SEDAN":
      await handleVehicleChoice(psid, session, "sedan");
      break;

    case "VEHICLE_SUV":
      await handleVehicleChoice(psid, session, "suv");
      break;

    case "SEND_DRIVER_MESSAGE":
      await promptDriverMessage(psid);
      break;

    default:
      console.log("Unknown postback payload:", payload);
      await sendMainMenu(psid, "I'm not sure what that was. Here's what I can help with:");
  }
}

// ---------------------------------------------------------------------------
// WELCOME & MAIN MENU
// ---------------------------------------------------------------------------
async function sendWelcomeMessage(psid: string) {
  const user = await getFbUser(psid);
  const name = user?.first_name ?? "there";

  // 1. Greeting with privacy policy link button
  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: `👋 Hi ${name}! Welcome to Hatid Sundo — your reliable ride service!\n\nBy continuing, you agree to our Privacy Policy. Please take a moment to review it before getting started.`,
        buttons: [
          {
            type: "web_url",
            url: PRIVACY_POLICY_URL,
            title: "📋 Privacy Policy",
            webview_height_ratio: "tall",
          },
        ],
      },
    },
  });

  // 2. Main menu
  await sendMainMenu(psid);
}


async function sendMainMenu(psid: string, intro?: string) {
  if (intro) {
    await sendMessage(psid, { text: intro });
  }

  const trip = await getActiveTrip(psid);
  let buttons: any[] = [];

  if (trip && (trip.status === "pending" || trip.status === "offered")) {
    buttons = [
      { type: "postback", title: "📍 Check Status", payload: "CHECK_STATUS" },
      { type: "postback", title: "❌ Cancel Request", payload: "CANCEL_RIDE" },
      { type: "postback", title: "🧑 Talk to Agent", payload: "TALK_TO_HUMAN" },
    ];
  } else if (trip) {
    buttons = [
      { type: "postback", title: "📍 Check Status", payload: "CHECK_STATUS" },
      { type: "postback", title: "💬 Message Driver", payload: "SEND_DRIVER_MESSAGE" },
      { type: "postback", title: "🧑 Talk to Agent", payload: "TALK_TO_HUMAN" },
    ];
  } else {
    buttons = [
      { type: "postback", title: "🚗 Book a Ride", payload: "BOOK_RIDE" },
      { type: "postback", title: "📍 Check Status", payload: "CHECK_STATUS" },
      { type: "postback", title: "🧑 Talk to Agent", payload: "TALK_TO_HUMAN" },
    ];
  }

  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: "Choose an option below:",
        buttons: buttons,
      },
    },
  });
}

// ---------------------------------------------------------------------------
// BOOKING FLOW
// ---------------------------------------------------------------------------
async function startBookingFlow(psid: string) {
  await clearSession(psid);
  await setSession(psid, "awaiting_pickup", {});

  const mapBaseUrl = Deno.env.get("MAP_WEBVIEW_URL") || "https://your-marketing-site.com/map.html";
  // Single map load — user sets both pickup & destination in one session
  const mapUrl = `${mapBaseUrl}?psid=${psid}`;

  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: "🚗 Let's book your ride!\n\nTap the button below to open the map. You'll pin your pickup location first, then your destination — all in one go!",
        buttons: [
          {
            type: "web_url",
            url: mapUrl,
            title: "🗺️ Open Map",
            webview_height_ratio: "tall",
            messenger_extensions: true,
          }
        ]
      }
    }
  });
}

async function handlePickupText(psid: string, session: BotSession, text: string) {
  // User typed an address instead of using the map.
  // Store it and ask them to open the map to pin destination.
  const data: SessionData = { ...session.data, pickup_addr: text };
  await setSession(psid, "awaiting_pickup", data);

  const mapBaseUrl = Deno.env.get("MAP_WEBVIEW_URL") || "https://your-marketing-site.com/map.html";
  const mapUrl = `${mapBaseUrl}?psid=${psid}`;

  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: `Got it! Please use the map to confirm both your pickup and destination.`,
        buttons: [
          {
            type: "web_url",
            url: mapUrl,
            title: "🗺️ Open Map",
            webview_height_ratio: "tall",
            messenger_extensions: true,
          }
        ]
      }
    }
  });
}

async function handleDestinationText(psid: string, session: BotSession, text: string) {
  const data: SessionData = { ...session.data, dest_addr: text };
  await setSession(psid, "awaiting_vehicle", data);
  await askVehicleType(psid);
}

async function handleLocationAttachment(
  psid: string,
  session: BotSession,
  coords: { lat: number; long: number }
) {
  // Native Messenger location pin shared while in awaiting_pickup state.
  // Store as pickup and prompt them to use the map for destination too.
  const lat = coords.lat;
  const lng = coords.long;
  const addr = await reverseGeocode(lat, lng);

  const data: SessionData = {
    ...session.data,
    pickup_lat: lat,
    pickup_lng: lng,
    pickup_addr: addr,
  };
  await setSession(psid, "awaiting_pickup", data);

  const mapBaseUrl = Deno.env.get("MAP_WEBVIEW_URL") || "https://your-marketing-site.com/map.html";
  const mapUrl = `${mapBaseUrl}?psid=${psid}`;

  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: `📍 Got your location!\n\nNow please open the map to confirm your pickup pin and set your destination.`,
        buttons: [
          {
            type: "web_url",
            url: mapUrl,
            title: "🗺️ Open Map",
            webview_height_ratio: "tall",
            messenger_extensions: true,
          }
        ]
      }
    }
  });
}

async function askVehicleType(psid: string) {
  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: "Choose your vehicle type:",
        buttons: [
          { type: "postback", title: "🏍️ Motorcycle", payload: "VEHICLE_MOTORCYCLE" },
          { type: "postback", title: "🚗 Sedan", payload: "VEHICLE_SEDAN" },
          { type: "postback", title: "🚙 SUV", payload: "VEHICLE_SUV" },
        ],
      },
    },
  });
}

async function handleVehicleChoice(psid: string, session: BotSession, vehicleText: string) {
  // Normalize input (handles both postback and text)
  let vehicle = "motorcycle";
  const lower = vehicleText.toLowerCase();
  if (lower.includes("sedan") || lower.includes("car")) vehicle = "sedan";
  else if (lower.includes("suv") || lower.includes("van")) vehicle = "suv";
  else if (lower.includes("motor") || lower.includes("bike")) vehicle = "motorcycle";

  const data: SessionData = { ...session.data, vehicle_type: vehicle };
  await setSession(psid, "awaiting_confirm", data);
  await showBookingSummary(psid, data);
}

async function showBookingSummary(psid: string, data: SessionData) {
  const vehicleEmoji = data.vehicle_type === "sedan" ? "🚗" : data.vehicle_type === "suv" ? "🚙" : "🏍️";
  const vehicleLabel = (data.vehicle_type ?? "motorcycle").charAt(0).toUpperCase() + (data.vehicle_type ?? "motorcycle").slice(1);

  const pLat = data.pickup_lat ?? 11.1090;
  const pLng = data.pickup_lng ?? 125.0210;
  const dLat = data.dest_lat ?? 11.1090;
  const dLng = data.dest_lng ?? 125.0210;
  
  const straightLineKm = getDistanceFromLatLonInKm(pLat, pLng, dLat, dLng);
  const estimatedKm = straightLineKm * 1.3; // Road network multiplier
  // calculateFare mirrors FareSettings.calculateFare() from fare_settings_service.dart
  const estimatedFare = await calculateFare(data.vehicle_type ?? "motorcycle", estimatedKm);

  const pickup = data.pickup_addr ?? "Your location";
  const dest = data.dest_addr ?? "Your destination";

  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: `🧾 Booking Summary\n\n📍 From: ${pickup}\n🏁 To: ${dest}\n${vehicleEmoji} Vehicle: ${vehicleLabel}\n💰 Est. Fare: ₱${estimatedFare.toFixed(0)}+\n💳 Payment: Cash\n\nReady to confirm?`,
        buttons: [
          { type: "postback", title: "✅ Confirm Booking", payload: "CONFIRM_BOOKING" },
          { type: "postback", title: "❌ Cancel", payload: "ABORT_BOOKING" },
        ],
      },
    },
  });
}

async function handleConfirmChoice(psid: string, session: BotSession, lower: string) {
  if (lower.includes("confirm") || lower.includes("yes") || lower.includes("oo") || lower.includes("sige")) {
    await executeBooking(psid, session);
  } else if (lower.includes("cancel") || lower.includes("no") || lower.includes("hindi") || lower.includes("abort")) {
    await clearSession(psid);
    await sendMessage(psid, { text: "Booking cancelled. Let me know if you need anything else!" });
    await sendMainMenu(psid);
  } else {
    // Re-show summary
    await showBookingSummary(psid, session.data);
  }
}

async function executeBooking(psid: string, session: BotSession) {
  const data = session.data;

  if (!data.pickup_addr && !data.pickup_lat) {
    await sendMessage(psid, { text: "Something went wrong — I lost your pickup location. Let's start again." });
    await startBookingFlow(psid);
    return;
  }

  await sendMessage(psid, { text: "⏳ Creating your booking..." });

  try {
    const supabase = getSupabase();

    // Get or create the user in Supabase
    const userId = await getOrCreateSupabaseUser(psid);
    if (!userId) throw new Error("Could not create user account");

    // Use coords if provided, else use placeholder (geocoding would be done server-side in production)
    const pickupLat = data.pickup_lat ?? 11.1090; // Tanauan, Leyte fallback
    const pickupLng = data.pickup_lng ?? 125.0210;
    const destLat = data.dest_lat ?? 11.1090;
    const destLng = data.dest_lng ?? 125.0210;

      const calculatedDistance = getDistanceFromLatLonInKm(pickupLat, pickupLng, destLat, destLng) * 1.3;
      
      // calculateFare mirrors FareSettings.calculateFare() from fare_settings_service.dart
      // — reads live settings from fare_settings table, applies night multiplier only to destKm.
      const finalEstimatedFare = await calculateFare(data.vehicle_type ?? "motorcycle", calculatedDistance);
      
      console.log(`[executeBooking] psid=${psid} distance=${calculatedDistance} fare=${finalEstimatedFare}`);
      
      const tripData = {
        id: crypto.randomUUID(),
        client_id: userId,
        pickup_lat: pickupLat,
        pickup_lng: pickupLng,
        pickup_address: data.pickup_addr ?? "",
        dest_lat: destLat,
        dest_lng: destLng,
        dest_address: data.dest_addr ?? "",
        status: "pending",
        vehicle_type: data.vehicle_type ?? "motorcycle",
        payment_method: "cash",
        payment_status: "pending",
        fare_estimated: finalEstimatedFare,
        fare_final: finalEstimatedFare, // Pre-fill fare_final to prevent complete_trip_rpc from falling back to 25 if possible
        distance_km: calculatedDistance,
        duration_min: Math.round((calculatedDistance / 30) * 60), // rough estimate at 30km/h
        created_at: new Date().toISOString(),
      };

    const { data: insertedTrip, error: tripError } = await supabase
      .from("trips")
      .insert(tripData)
      .select()
      .single();

    if (tripError) throw tripError;

    // Store trip_id in session so we can look it up for status checks
    await supabase.from("fb_users").update({ user_id: userId }).eq("psid", psid);
    await clearSession(psid);

    // Notify nearby drivers (fire-and-forget)
    notifyDrivers(insertedTrip.id, pickupLat, pickupLng).catch(() => {});

    await sendMessage(psid, {
      attachment: {
        type: "template",
        payload: {
          template_type: "button",
          text: `✅ Ride booked successfully!\n\n🆔 Booking #${insertedTrip.id.substring(0, 8).toUpperCase()}\n📍 From: ${data.pickup_addr ?? "Your location"}\n🏁 To: ${data.dest_addr ?? "Your destination"}\n\nWe're finding you a driver nearby. You'll be notified once one accepts your request!\n\nTypically takes 2–5 minutes.`,
          buttons: [
            { type: "postback", title: "📍 Check Status", payload: "CHECK_STATUS" },
            { type: "postback", title: "❌ Cancel Request", payload: "CANCEL_RIDE" },
          ],
        },
      },
    });
  } catch (err) {
    console.error("Booking error:", err);
    await clearSession(psid);
    await sendMessage(psid, {
      text: "😔 Sorry, something went wrong while creating your booking. Please try again or talk to an agent.",
    });
    await sendMainMenu(psid);
  }
}

// ---------------------------------------------------------------------------
// FARE SETTINGS — mirrors lib/services/fare_settings_service.dart
// ---------------------------------------------------------------------------
interface FareSettings {
  baseFare: number;
  baseFareMotorcycle: number;
  baseFareSedan: number;
  baseFareSuv: number;
  perKmRate: number;
  perKmRateMotorcycle: number;
  perKmRateSedan: number;
  perKmRateSuv: number;
  nightRateMultiplier: number;
  nightStartHour: number;
  nightEndHour: number;
}

/** Fetch fare settings from the DB; falls back to the same defaults as Dart. */
async function fetchFareSettings(): Promise<FareSettings> {
  try {
    const supabase = getSupabase();
    const { data, error } = await supabase
      .from("fare_settings")
      .select("*")
      .eq("id", 1)
      .single();
    if (error || !data) throw error;
    return {
      baseFare:              Number(data.base_fare)               || 25.0,
      baseFareMotorcycle:    Number(data.base_fare_motorcycle)    || 20.0,
      baseFareSedan:         Number(data.base_fare_sedan)         || 25.0,
      baseFareSuv:           Number(data.base_fare_suv)           || 35.0,
      perKmRate:             Number(data.per_km_rate)             || 8.0,
      perKmRateMotorcycle:   Number(data.per_km_rate_motorcycle)  || 6.0,
      perKmRateSedan:        Number(data.per_km_rate_sedan)       || 8.0,
      perKmRateSuv:          Number(data.per_km_rate_suv)         || 12.0,
      nightRateMultiplier:   Number(data.night_rate_multiplier)   || 1.2,
      nightStartHour:        Number(data.night_start_hour)        || 21,
      nightEndHour:          Number(data.night_end_hour)          || 5,
    };
  } catch (_) {
    // Return the same defaults as the Dart FareSettings() constructor
    return {
      baseFare: 25.0, baseFareMotorcycle: 20.0, baseFareSedan: 25.0, baseFareSuv: 35.0,
      perKmRate: 8.0, perKmRateMotorcycle: 6.0, perKmRateSedan: 8.0, perKmRateSuv: 12.0,
      nightRateMultiplier: 1.2, nightStartHour: 21, nightEndHour: 5,
    };
  }
}

/** Mirrors FareSettings.getBaseFare() */
function getBaseFare(fs: FareSettings, vehicleType: string): number {
  switch (vehicleType.toLowerCase()) {
    case 'motorcycle': return fs.baseFareMotorcycle;
    case 'sedan':      return fs.baseFareSedan;
    case 'suv':        return fs.baseFareSuv;
    default:           return fs.baseFare;
  }
}

/** Mirrors FareSettings.getPerKmRate() */
function getPerKmRate(fs: FareSettings, vehicleType: string): number {
  switch (vehicleType.toLowerCase()) {
    case 'motorcycle': return fs.perKmRateMotorcycle;
    case 'sedan':      return fs.perKmRateSedan;
    case 'suv':        return fs.perKmRateSuv;
    default:           return fs.perKmRate;
  }
}

/** Mirrors FareSettings.isNightTime() — uses device-local PHT (UTC+8) */
function isNightTime(fs: FareSettings): boolean {
  const utcHour = new Date().getUTCHours();
  const phtHour = (utcHour + 8) % 24;
  return phtHour >= fs.nightStartHour || phtHour < fs.nightEndHour;
}

/**
 * Mirrors FareSettings.calculateFare() exactly:
 *   base + floor(driverPickupKm) * rate
 *        + floor(destKm)         * rate * nightMultiplier
 *
 * driverPickupKm is always 0 in the Messenger context (driver not yet assigned).
 */
async function calculateFare(
  vehicleType: string,
  destKm: number,
  driverPickupKm = 0.0
): Promise<number> {
  const fs = await fetchFareSettings();
  const base     = getBaseFare(fs, vehicleType);
  const rate     = getPerKmRate(fs, vehicleType);
  const nightMul = isNightTime(fs) ? fs.nightRateMultiplier : 1.0;

  return base
    + Math.floor(driverPickupKm) * rate
    + Math.floor(destKm) * rate * nightMul;
}

function getDistanceFromLatLonInKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const R = 6371; // Radius of the earth in km
  const dLat = deg2rad(lat2 - lat1);
  const dLon = deg2rad(lon2 - lon1); 
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * 
    Math.sin(dLon/2) * Math.sin(dLon/2); 
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
  return R * c;
}

function deg2rad(deg: number) {
  return deg * (Math.PI/180);
}

// Notify nearby drivers via match_driver Edge Function (best-effort)
async function notifyDrivers(tripId: string, lat: number, lng: number) {
  const url = `${SUPABASE_URL}/functions/v1/match_driver`;
  await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
    },
    body: JSON.stringify({ trip_id: tripId, pickup_lat: lat, pickup_lng: lng }),
  });
}

// ---------------------------------------------------------------------------
// CHECK STATUS
// ---------------------------------------------------------------------------
async function checkStatus(psid: string) {
  try {
    const trip = await getActiveTrip(psid);

    if (!trip) {
      await sendMessage(psid, {
        text: "📭 You don't have any active rides right now.",
      });
      await sendMessage(psid, {
        attachment: {
          type: "template",
          payload: {
            template_type: "button",
            text: "Would you like to book one?",
            buttons: [
              { type: "postback", title: "🚗 Book a Ride", payload: "BOOK_RIDE" },
            ],
          },
        },
      });
      return;
    }

    const statusLabel = formatTripStatus(trip.status);
    const vehicleEmoji = trip.vehicle_type === "sedan" ? "🚗" : trip.vehicle_type === "suv" ? "🚙" : "🏍️";
    const fare = trip.fare_final ?? trip.fare_estimated;

    let statusDetails = `🛺 Your Current Ride\n\n`;
    statusDetails += `🆔 #${trip.id.substring(0, 8).toUpperCase()}\n`;
    statusDetails += `📌 Status: ${statusLabel}\n`;

    if (trip.rider_id) {
      try {
        const supabase = getSupabase();
        const { data: profile } = await supabase.from('rider_profiles').select('vehicle_color, vehicle_make, vehicle_model, plate_number').eq('user_id', trip.rider_id).maybeSingle();
        const { data: user } = await supabase.from('users').select('name').eq('id', trip.rider_id).maybeSingle();

        if (user && profile) {
          const driverName = user.name ?? 'Your driver';
          const vehicle = `${profile.vehicle_color || ''} ${profile.vehicle_make || ''} ${profile.vehicle_model || ''}`.trim();
          const plate = profile.plate_number || '';
          
          if (vehicle || plate) {
             statusDetails += `👤 Driver: ${driverName}\n🚘 Vehicle: ${vehicle} (${plate})\n`;
          } else {
             statusDetails += `👤 Driver: ${driverName}\n`;
          }
        }
      } catch (e) {
        console.error("Failed to fetch driver info for status:", e);
      }
    }

    statusDetails += `📍 From: ${trip.pickup_address ?? "N/A"}\n`;
    statusDetails += `🏁 To: ${trip.dest_address ?? "N/A"}\n`;
    statusDetails += `${vehicleEmoji} Type: ${(trip.vehicle_type ?? "motorcycle").charAt(0).toUpperCase() + (trip.vehicle_type ?? "motorcycle").slice(1)}\n`;
    statusDetails += `💰 Est. Fare: ₱${Number(fare).toFixed(0)}`;

    const buttons: any[] = [
      { type: "postback", title: "💬 Message Driver", payload: "SEND_DRIVER_MESSAGE" },
    ];

    // Only show cancel if trip is still pending
    if (trip.status === "pending") {
      buttons.push({ type: "postback", title: "❌ Cancel Request", payload: "CANCEL_RIDE" });
    }

    await sendMessage(psid, {
      attachment: {
        type: "template",
        payload: {
          template_type: "button",
          text: statusDetails,
          buttons: buttons.slice(0, 3), // Max 3 buttons
        },
      },
    });
  } catch (err) {
    console.error("Check status error:", err);
    await sendMessage(psid, { text: "Sorry, I couldn't retrieve your status. Please try again." });
  }
}

function formatTripStatus(status: string): string {
  const map: Record<string, string> = {
    pending: "⏳ Looking for a driver...",
    offered: "📨 Driver offer sent",
    accepted: "🚗 Driver is on the way to pick you up",
    driver_arriving: "📍 Driver has arrived at your location!",
    in_progress: "🏁 Trip in progress",
    completed: "✅ Trip completed",
    cancelled: "❌ Cancelled",
  };
  return map[status] ?? status;
}

// ---------------------------------------------------------------------------
// CANCEL RIDE
// ---------------------------------------------------------------------------
async function initiateCancelRide(psid: string) {
  const trip = await getActiveTrip(psid);

  if (!trip) {
    await sendMessage(psid, { text: "You don't have an active ride to cancel." });
    await sendMainMenu(psid);
    return;
  }

  if (trip.status !== "pending") {
    await sendMessage(psid, {
      text: `Your ride is currently "${formatTripStatus(trip.status)}" — it can only be cancelled while we're still looking for a driver.\n\nPlease talk to an agent if you need help.`,
    });
    await sendMainMenu(psid);
    return;
  }

  await sendMessage(psid, {
    attachment: {
      type: "template",
      payload: {
        template_type: "button",
        text: "Are you sure you want to cancel your ride?",
        buttons: [
          { type: "postback", title: "Yes, Cancel", payload: "CONFIRM_CANCEL" },
          { type: "postback", title: "No, Keep Ride", payload: "CHECK_STATUS" },
        ],
      },
    },
  });
}

async function executeCancelRide(psid: string) {
  try {
    const trip = await getActiveTrip(psid);
    if (!trip) {
      await sendMessage(psid, { text: "No active ride found to cancel." });
      return;
    }

    const supabase = getSupabase();
    await supabase
      .from("trips")
      .update({
        status: "cancelled",
        cancelled_by: null,
        cancellation_reason: "Cancelled by client via Messenger",
        cancelled_at: new Date().toISOString(),
      })
      .eq("id", trip.id);

    await sendMessage(psid, {
      text: "✅ Your ride has been cancelled.\n\nSorry to see you go! Let us know if you need a ride in the future.",
    });
    await sendMainMenu(psid);
  } catch (err) {
    console.error("Cancel ride error:", err);
    await sendMessage(psid, { text: "Sorry, I couldn't cancel your ride. Please contact an agent." });
  }
}

// ---------------------------------------------------------------------------
// DRIVER MESSAGE RELAY
// ---------------------------------------------------------------------------
async function promptDriverMessage(psid: string) {
  const trip = await getActiveTrip(psid);
  if (!trip) {
    await sendMessage(psid, { text: "You don't have an active ride right now. You can only message the driver during an active trip." });
    return;
  }

  if (trip.status === "pending") {
    await sendMessage(psid, { text: "⏳ We're still looking for a driver for you. Once one accepts, you'll be able to message them." });
    return;
  }

  await sendMessage(psid, {
    text: "💬 Go ahead! Type your message to the driver and I'll relay it:",
  });

  // Set a temporary session hint so next text goes to driver
  await setSession(psid, "awaiting_destination", { ...{}, pickup_addr: "__relay__" });
  // Actually, we handle this differently — any text during an active trip is relayed.
  // Reset session to idle so the idle handler picks up the driver relay logic.
  await clearSession(psid);
}

async function relayMessageToDriver(psid: string, trip: TripRow, text: string) {
  try {
    const userId = await getOrCreateSupabaseUser(psid);
    if (!userId || !trip.rider_id) {
      await sendMessage(psid, { text: "I couldn't relay your message — the driver may not have been assigned yet." });
      return;
    }

    const supabase = getSupabase();
    await supabase.from("messages").insert({
      id: crypto.randomUUID(),
      trip_id: trip.id,
      sender_id: userId,
      sender_role: "client",
      content: text,
      message_type: "text",
      is_read: false,
      created_at: new Date().toISOString(),
    });

    // Notify the driver via the existing send_notification function
    notifyDriver(trip.rider_id, text).catch(() => {});

    await sendMessage(psid, {
      text: `✅ Message sent to your driver:\n"${text}"\n\nThey'll see it in the Hatid Sundo app.`,
    });
  } catch (err) {
    console.error("Relay message error:", err);
    await sendMessage(psid, { text: "Sorry, I couldn't deliver your message. Please try again." });
  }
}

async function notifyDriver(riderId: string, messageText: string) {
  const url = `${SUPABASE_URL}/functions/v1/send_notification`;
  await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${SUPABASE_SERVICE_KEY}`,
    },
    body: JSON.stringify({
      user_id: riderId,
      title: "New message from client",
      body: messageText,
      data: { type: "message" },
    }),
  });
}

// ---------------------------------------------------------------------------
// HUMAN HANDOVER (Facebook Handover Protocol)
// ---------------------------------------------------------------------------
async function handleHumanHandover(psid: string) {
  await sendMessage(psid, {
    text: "👤 Connecting you to a live agent...\n\nA member of our team will be with you shortly. Our operating hours are Monday–Saturday, 8AM–8PM.",
  });

  // Mark session as handed over so bot stops responding
  await setSession(psid, "handover", {});

  // Pass thread control to the Inbox app (secondary receiver)
  // The Inbox app ID for Facebook is a well-known constant
  const INBOX_APP_ID = FB_APP_ID || "263902037430900"; // Facebook Page Inbox app ID

  try {
    const res = await fetch(`${GRAPH_API}/me/pass_thread_control?access_token=${PAGE_ACCESS_TOKEN}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        recipient: { id: psid },
        target_app_id: INBOX_APP_ID,
        metadata: "Customer requested live agent via Messenger bot",
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error("Handover Protocol error:", errText);
      await clearSession(psid);
      await sendMessage(psid, {
        text: "⚠️ I wasn't able to connect you automatically. Please message our Page directly or call us.",
      });
    } else {
      console.log("Thread control passed to Inbox for PSID:", psid);
    }
  } catch (err) {
    console.error("Handover request failed:", err);
    await clearSession(psid);
  }
}

async function takeThreadControlBack(psid: string) {
  try {
    const res = await fetch(`${GRAPH_API}/me/take_thread_control?access_token=${PAGE_ACCESS_TOKEN}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        recipient: { id: psid },
        metadata: "Bot taking back control via user keyword",
      }),
    });
    
    if (!res.ok) {
        const text = await res.text();
        console.error("Take thread control failed with:", text);
    } else {
        console.log("Thread control taken back by Bot for PSID:", psid);
    }
  } catch (err) {
    console.error("Take thread control failed:", err);
  }
}

// ---------------------------------------------------------------------------
// SUPABASE HELPERS
// ---------------------------------------------------------------------------

async function getOrCreateFbUser(psid: string): Promise<void> {
  const supabase = getSupabase();

  const { data: existing } = await supabase
    .from("fb_users")
    .select("psid")
    .eq("psid", psid)
    .maybeSingle();

  if (!existing) {
    // Fetch profile from Facebook Graph API
    const profile = await fetchFbProfile(psid);

    await supabase.from("fb_users").insert({
      psid,
      name: profile?.name ?? null,
      first_name: profile?.first_name ?? null,
      last_name: profile?.last_name ?? null,
      avatar_url: profile?.profile_pic ?? null,
    });
  }
}

async function getFbUser(psid: string) {
  const supabase = getSupabase();
  const { data } = await supabase
    .from("fb_users")
    .select("*")
    .eq("psid", psid)
    .maybeSingle();
  return data;
}

async function getOrCreateSupabaseUser(psid: string): Promise<string | null> {
  const supabase = getSupabase();

  // Check if fb_user already has a linked user_id
  const { data: fbUser } = await supabase
    .from("fb_users")
    .select("user_id, first_name, last_name, name")
    .eq("psid", psid)
    .maybeSingle();

  if (!fbUser) return null;
  if (fbUser.user_id) return fbUser.user_id;

  // Create a new guest client user in Supabase auth + users table
  // We use a stable pseudo-email so duplicate signups don't happen
  const pseudoEmail = `fb_${psid}@messenger.hatidsundo.app`;
  const displayName =
    fbUser.name ??
    (`${fbUser.first_name ?? ""} ${fbUser.last_name ?? ""}`.trim() || "Messenger User");

  // Create auth user (signUp with email+password for service-role bypasses email confirmation)
  const { data: authData, error: authError } = await supabase.auth.admin.createUser({
    email: pseudoEmail,
    password: crypto.randomUUID(), // Random — user will never use this
    email_confirm: true,
    user_metadata: { name: displayName, role: "client" },
  });

  if (authError && !authError.message.includes("already been registered")) {
    console.error("Auth create user error:", authError);
    return null;
  }

  // Get the user ID (either newly created or existing)
  let newUserId = authData?.user?.id;
  if (!newUserId) {
    // User already existed — look them up
    const { data: existingAuth } = await supabase.auth.admin.listUsers();
    const found = existingAuth?.users?.find((u) => u.email === pseudoEmail);
    newUserId = found?.id;
  }

  if (!newUserId) return null;

  // Upsert into users table
  await supabase.from("users").upsert({
    id: newUserId,
    email: pseudoEmail,
    name: displayName,
    role: "client",
    is_active: true,
  });

  // Link back to fb_users
  await supabase.from("fb_users").update({ user_id: newUserId }).eq("psid", psid);

  return newUserId;
}

async function getSession(psid: string): Promise<BotSession> {
  const supabase = getSupabase();
  const { data } = await supabase
    .from("bot_sessions")
    .select("*")
    .eq("psid", psid)
    .maybeSingle();

  return data ?? { psid, state: "idle", data: {} };
}

async function setSession(psid: string, state: SessionState, data: SessionData): Promise<void> {
  const supabase = getSupabase();
  await supabase.from("bot_sessions").upsert(
    { psid, state, data, updated_at: new Date().toISOString() },
    { onConflict: "psid" }
  );
}

async function clearSession(psid: string): Promise<void> {
  const supabase = getSupabase();
  await supabase
    .from("bot_sessions")
    .upsert(
      { psid, state: "idle", data: {}, updated_at: new Date().toISOString() },
      { onConflict: "psid" }
    );
}

async function getActiveTrip(psid: string): Promise<TripRow | null> {
  const supabase = getSupabase();

  const { data: fbUser } = await supabase
    .from("fb_users")
    .select("user_id")
    .eq("psid", psid)
    .maybeSingle();

  if (!fbUser?.user_id) return null;

  const { data: trip } = await supabase
    .from("trips")
    .select("*")
    .eq("client_id", fbUser.user_id)
    .in("status", ["pending", "offered", "accepted", "driver_arriving", "in_progress"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return trip ?? null;
}

// ---------------------------------------------------------------------------
// FACEBOOK GRAPH API HELPERS
// ---------------------------------------------------------------------------

async function fetchFbProfile(psid: string): Promise<FbProfile | null> {
  try {
    const res = await fetch(
      `${GRAPH_API}/${psid}?fields=first_name,last_name,name,profile_pic&access_token=${PAGE_ACCESS_TOKEN}`
    );
    if (res.ok) return await res.json();
    console.error("FB profile fetch failed:", await res.text());
  } catch (err) {
    console.error("FB profile fetch error:", err);
  }
  return null;
}

async function sendMessage(psid: string, message: object): Promise<void> {
  const body = {
    recipient: { id: psid },
    message,
    messaging_type: "RESPONSE",
  };

  try {
    const res = await fetch(`${GRAPH_API}/me/messages?access_token=${PAGE_ACCESS_TOKEN}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const err = await res.text();
      console.error("Send API error:", err);
    }
  } catch (err) {
    console.error("Send API fetch error:", err);
  }
}

// ---------------------------------------------------------------------------
// GEOCODING HELPER
// ---------------------------------------------------------------------------
async function reverseGeocode(lat: number, lng: number): Promise<string> {
  try {
    // Using Nominatim (OpenStreetMap) — free, no API key needed
    const res = await fetch(
      `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`,
      { headers: { "User-Agent": "HatidSundo/1.0 (contact@hatidsundo.app)" } }
    );
    if (res.ok) {
      const data = await res.json();
      return data.display_name ?? `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
    }
  } catch (_) {
    // Silently fall through
  }
  return `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
}
