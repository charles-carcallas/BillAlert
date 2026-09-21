import { assertEquals } from "jsr:@std/assert";
import { handler as sendSmsHandler } from "../send-sms/index.ts";
import { handler as webhookHandler } from "../httpsms-webhook/index.ts";
import * as jose from "npm:jose@5.2.4";

const notificationId = "00000000-0000-4000-8000-000000000001";
const eventAt = "2026-09-19T00:00:00Z";
// Dummy masked values only. All HTTP is intercepted; no real credentials.
const environment: Record<string, string> = {
  SMS_CRON_SECRET: "test-cron-secret",
  SUPABASE_URL: "https://mock.invalid",
  SUPABASE_SERVICE_ROLE_KEY: "mock-service-key",
  HTTPSMS_API_KEY: "mock-api-key",
  HTTPSMS_PHONE_NUMBER: "+63956****934",
  HTTPSMS_WEBHOOK_SIGNING_KEY: "mock-signing-key",
};
type Call = { url: string; body: Record<string, unknown> };

async function isolated(run: (calls: Call[]) => Promise<void>, rpcFails = false) {
  const saved = new Map(Object.keys(environment).map((key) => [key, Deno.env.get(key)]));
  const originalFetch = globalThis.fetch;
  const calls: Call[] = [];
  for (const [key, value] of Object.entries(environment)) Deno.env.set(key, value);
  globalThis.fetch = async (input, options) => {
    const req = new Request(input, options);
    const body = req.method === "GET" ? {} : JSON.parse(await req.text() || "{}");
    calls.push({ url: req.url, body });
    const path = new URL(req.url).pathname;
    if (path.endsWith("/fn_queue_overdue_sms")) return Response.json({ queued: 1 });
    if (path.endsWith("/settings")) return Response.json({ batch_delay_ms: 0 });
    if (path.endsWith("/fn_claim_sms_batch")) return Response.json([
      { id: notificationId, destination_number: "+63956****934", message_content: "Test" },
    ]);
    if (req.url === "https://api.httpsms.com/v1/messages/send") {
      return Response.json({ data: { id: "gw-1" } });
    }
    if (path.endsWith("/fn_apply_sms_event") && rpcFails) {
      return Response.json({ message: "No matching notification" }, { status: 400 });
    }
    if (path.endsWith("/notifications") || path.endsWith("/fn_record_sms_acceptance") ||
        path.endsWith("/fn_apply_sms_event")) return new Response(null, { status: 204 });
    throw new Error("Unexpected mocked request: " + path);
  };
  try {
    await run(calls);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of saved) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

async function webhook(event: string, data: Record<string, unknown>, valid = true) {
  const token = valid ? await new jose.SignJWT({})
    .setProtectedHeader({ alg: "HS256" }).setExpirationTime("5m")
    .sign(new TextEncoder().encode(environment.HTTPSMS_WEBHOOK_SIGNING_KEY)) : "invalid";
  return webhookHandler(new Request("http://localhost/httpsms-webhook", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "X-Event-Type": event },
    body: JSON.stringify({ id: "event-1", data }),
  }));
}

Deno.test("send-sms: rejects invalid cron secret without HTTP", () => isolated(async (calls) => {
  const response = await sendSmsHandler(new Request("http://localhost/send-sms", {
    method: "POST", headers: { "x-sms-cron-secret": "wrong" },
  }));
  assertEquals(response.status, 401);
  assertEquals(calls.length, 0);
}));

Deno.test("send-sms: sends notification reference and records acceptance", () => isolated(async (calls) => {
  const response = await sendSmsHandler(new Request("http://localhost/send-sms", {
    method: "POST", headers: { "x-sms-cron-secret": environment.SMS_CRON_SECRET },
  }));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).summary, {
    queued: 1, claimed: 1, accepted: 1, failed: 0, uncertain: 0,
  });
  assertEquals(calls.find((c) => c.url.includes("api.httpsms.com"))?.body, {
    from: environment.HTTPSMS_PHONE_NUMBER, to: "+63956****934",
    content: "Test", request_id: notificationId,
  });
  const acceptance = calls.find((c) => c.url.endsWith("/fn_record_sms_acceptance"));
  assertEquals(acceptance?.body.p_notification, notificationId);
  assertEquals(acceptance?.body.p_gateway_id, "gw-1");
}));

Deno.test("webhook: rejects invalid signature without HTTP", () => isolated(async (calls) => {
  assertEquals((await webhook("message.phone.sent", {}, false)).status, 401);
  assertEquals(calls.length, 0);
}));

for (const event of ["message.phone.sent", "message.phone.delivered", "message.send.failed", "message.send.expired"]) {
  Deno.test("webhook: forwards " + event + " with request ID", () => isolated(async (calls) => {
    const response = await webhook(event, {
      ...(event.endsWith("expired") ? { message_id: "gw-1", is_final: true } : { id: "gw-1" }),
      request_id: notificationId, timestamp: eventAt, error_message: "fixture reason",
    });
    assertEquals(response.status, 200);
    assertEquals(calls.length, 1);
    assertEquals(calls[0].body, {
      p_gateway_id: "gw-1", p_event_type: event, p_event_at: eventAt,
      p_reason: "fixture reason", p_request_id: notificationId,
    });
  }));
}

Deno.test("webhook: ignores non-final expiry without applying event", () => isolated(async (calls) => {
  assertEquals((await webhook("message.send.expired", { message_id: "gw-1", is_final: false })).status, 200);
  assertEquals(calls.length, 0);
}));

Deno.test("webhook: supports legacy payload without request ID", () => isolated(async (calls) => {
  assertEquals((await webhook("message.phone.sent", { id: "gw-1" })).status, 200);
  assertEquals(calls[0].body.p_request_id, null);
}));

Deno.test("webhook: returns failure when event could not be stored", () => isolated(async () => {
  assertEquals((await webhook("message.phone.sent", { id: "gw-unknown" })).status, 500);
}, true));
