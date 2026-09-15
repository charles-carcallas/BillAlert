import { createClient } from "npm:@supabase/supabase-js@2";
import * as jose from "npm:jose@5.2.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-event-type",
};

function reply(body: Record<string, unknown> | string, status = 200): Response {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), { 
    status, 
    headers: { ...corsHeaders, "Content-Type": typeof body === "string" ? "text/plain" : "application/json" } 
  });
}

const ALLOWED_EVENTS = [
  "message.phone.sent",
  "message.phone.delivered",
  "message.send.failed",
  "message.send.expired"
];

export const handler = async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return reply({ ok: false, error: "Use POST." }, 405);
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    // httpSMS only sends the Bearer token when the webhook has a signing key.
    console.error("Webhook refused: no Bearer token. Is a signing key set on the httpSMS webhook?");
    return reply({ ok: false, error: "Missing or invalid authorization" }, 401);
  }

  const token = authHeader.substring(7);
  const signingKey = Deno.env.get("HTTPSMS_WEBHOOK_SIGNING_KEY");
  
  if (!signingKey) {
    return reply({ ok: false, error: "Server configuration is incomplete." }, 500);
  }

  try {
    const secret = new TextEncoder().encode(signingKey);
    // A little clock tolerance: httpSMS sets iat/nbf from its own clock.
    await jose.jwtVerify(token, secret, { algorithms: ["HS256"], clockTolerance: 60 });
  } catch (e) {
    const code = (e as { code?: string })?.code ?? "unknown";
    console.error(`Webhook refused: token did not verify (${code}). HTTPSMS_WEBHOOK_SIGNING_KEY must equal the httpSMS webhook's signing key.`);
    return reply({ ok: false, error: "Invalid signature" }, 401);
  }

  const eventType = request.headers.get("X-Event-Type");
  if (!eventType || !ALLOWED_EVENTS.includes(eventType)) {
    console.error(`Webhook refused: event type "${eventType ?? "missing"}" is not handled.`);
    return reply({ ok: false, error: "Invalid or missing X-Event-Type" }, 400);
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    return reply({ ok: false, error: "Invalid JSON" }, 400);
  }

  const data = body.data || {};
  let gatewayId = data.id;
  if (eventType === "message.send.expired") {
    gatewayId = data.message_id;
  }

  if (!gatewayId) {
    return reply({ ok: false, error: "Missing gateway ID" }, 400);
  }

  const timestamp = data.timestamp || data.created_at || new Date().toISOString();
  const reason = data.error_message || null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  
  if (!supabaseUrl || !serviceRoleKey) {
    return reply({ ok: false, error: "Server configuration is incomplete." }, 500);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const maskedId = String(gatewayId).substring(0, 8) + "...";
  const eventId = body.id || "unknown";
  console.log(`Processing event ${eventId} for gateway ID ${maskedId}`);

  // httpSMS expires a message the phone has not confirmed, then sends it again
  // while attempts remain. Only the last expiry (is_final) means it gave up.
  if (eventType === "message.send.expired" && data.is_final !== true) {
    console.log(`Ignoring non-final expiry (attempt ${data.send_attempt_count ?? "?"}) for gateway ID ${maskedId}`);
    return reply("ok", 200);
  }

  const { error } = await adminClient.rpc("fn_apply_sms_event", {
    p_gateway_id: String(gatewayId),
    p_event_type: eventType,
    p_event_at: timestamp,
    p_reason: reason
  });

  if (error) {
    console.error("Error applying event:", error);
    return reply({ ok: false, error: "Failed to apply event" }, 500);
  }

  return reply("ok", 200);
}; 
Deno.serve(handler);
