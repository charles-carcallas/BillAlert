import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-sms-cron-secret",
};

function reply(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

// Keeps phone numbers out of the function log: "+639171234567" -> "…4567".
function maskPhoneNumbers(text: string): string {
  return text.replace(/\+?\d{6,}(\d{4})/g, "…$1");
}

// The first 8 hex characters of a secret's SHA-256. It can be compared with the
// digest the Supabase dashboard shows for a secret without revealing the value.
async function fingerprint(secret: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret));
  return Array.from(new Uint8Array(digest).slice(0, 4), (b) => b.toString(16).padStart(2, "0")).join("");
}

export const handler = async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return reply({ ok: false, error: "Use POST." }, 405);
  }

  const cronSecret = request.headers.get("x-sms-cron-secret");
  if (!cronSecret || cronSecret !== Deno.env.get("SMS_CRON_SECRET")) {
    return reply({ ok: false, error: "Unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("HTTPSMS_API_KEY");
  const fromNumber = Deno.env.get("HTTPSMS_PHONE_NUMBER");

  if (!supabaseUrl || !serviceRoleKey || !apiKey || !fromNumber) {
    return reply({ ok: false, error: "Server configuration is incomplete." }, 500);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const summary = {
    queued: 0,
    claimed: 0,
    accepted: 0,
    failed: 0,
    uncertain: 0
  };

  // 0. Move old claims to uncertain
  const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { error: resetError } = await adminClient.from("notifications")
    .update({ dispatch_state: "uncertain", failed_reason: "Claim timed out" })
    .eq("status", "pending")
    .eq("dispatch_state", "claimed")
    .lt("claimed_at", tenMinutesAgo);
  if (resetError) {
    console.error("Failed to reset old claims:", resetError);
  }

  // 1. Call fn_queue_overdue_sms
  const { data: queueData, error: queueError } = await adminClient.rpc("fn_queue_overdue_sms");
  if (queueError) {
    console.error("fn_queue_overdue_sms error:", queueError);
  }
  if (!queueError && queueData) {
    summary.queued = queueData.queued || 0;
  }

  // Fetch settings for delay
  const { data: settings, error: settingsError } = await adminClient.from("settings").select("batch_delay_ms").single();
  if (settingsError) {
    console.error("Failed to fetch settings:", settingsError);
  }
  const delayMs = settings?.batch_delay_ms ?? 1000;

  // 2. Claim a batch
  const claimToken = crypto.randomUUID();
  const { data: claimedRows, error: claimError } = await adminClient.rpc("fn_claim_sms_batch", {
    p_claim_token: claimToken
  });

  if (claimError) {
    return reply({ ok: false, error: "Failed to claim batch", details: claimError }, 500);
  }

  if (!claimedRows || claimedRows.length === 0) {
    return reply({ ok: true, summary });
  }

  summary.claimed = claimedRows.length;

  for (const row of claimedRows) {
    try {
      const response = await fetch("https://api.httpsms.com/v1/messages/send", {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          from: fromNumber,
          to: row.destination_number,
          content: row.message_content,
          request_id: row.id
        }),
        signal: AbortSignal.timeout(10000)
      });

      if (response.ok) {
        const body = await response.json();
        const gatewayId = body.data?.id;
        if (gatewayId) {
          const { error: accError } = await adminClient.rpc("fn_record_sms_acceptance", {
            p_notification: row.id,
            p_claim: claimToken,
            p_gateway_id: String(gatewayId),
            p_accepted_at: new Date().toISOString()
          });
          if (accError) console.error("fn_record_sms_acceptance error:", accError);
          summary.accepted++;
        } else {
          const { error: uncError } = await adminClient.rpc("fn_record_sms_uncertain", {
            p_notification: row.id,
            p_claim: claimToken,
            p_reason: "Malformed success response"
          });
          if (uncError) console.error("fn_record_sms_uncertain error:", uncError);
          summary.uncertain++;
        }
      } else if ([400, 401, 422].includes(response.status)) {
        let reason = `HTTP ${response.status}`;
        const rawBody = await response.text().catch(() => "");
        try {
          const errorBody = JSON.parse(rawBody);
          reason = errorBody.message || reason;
        } catch {
          // Not JSON; keep the status code as the reason.
        }
        // httpSMS names the rule that failed in `data`, while `message` is often
        // just "validation errors while sending message". The detail goes to the
        // function log rather than failed_reason, because the consumer's Inbox
        // shows failed_reason.
        console.error(`httpSMS refused notification ${row.id} with HTTP ${response.status}: ${maskPhoneNumbers(rawBody)}`);
        if (response.status === 401) {
          // httpSMS ignores phone keys (pk_) here; only the account key (uk_) works.
          console.error(`HTTPSMS_API_KEY in use: starts "${apiKey.slice(0, 3)}", ${apiKey.length} characters, SHA-256 starts ${await fingerprint(apiKey)}`);
        }
        const { error: failError } = await adminClient.rpc("fn_record_sms_definitive_failure", {
          p_notification: row.id,
          p_claim: claimToken,
          p_reason: reason
        });
        if (failError) console.error("fn_record_sms_definitive_failure error:", failError);
        summary.failed++;
      } else {
        const { error: uncError } = await adminClient.rpc("fn_record_sms_uncertain", {
          p_notification: row.id,
          p_claim: claimToken,
          p_reason: `HTTP ${response.status}`
        });
        if (uncError) console.error("fn_record_sms_uncertain error:", uncError);
        summary.uncertain++;
      }
    } catch (e) {
      const { error: uncError } = await adminClient.rpc("fn_record_sms_uncertain", {
        p_notification: row.id,
        p_claim: claimToken,
        p_reason: e instanceof Error ? e.message : "Unknown error"
      });
      if (uncError) console.error("fn_record_sms_uncertain error:", uncError);
      summary.uncertain++;
    }

    await new Promise(resolve => setTimeout(resolve, delayMs));
  }

  return reply({ ok: true, summary });
};
Deno.serve(handler);
