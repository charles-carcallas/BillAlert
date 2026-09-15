import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { handler as sendSmsHandler } from "../send-sms/index.ts";
import { handler as webhookHandler } from "../httpsms-webhook/index.ts";
import * as jose from "npm:jose";

// Mock Supabase Client and fetch
let fetchCalls: any[] = [];
let rpcCalls: any[] = [];
let selectCalls: any[] = [];

// Temporarily replace globals
const originalFetch = globalThis.fetch;
globalThis.fetch = async (...args) => {
  fetchCalls.push(args);
  return new Response(JSON.stringify({ data: { id: "mock-gateway-id" } }), { status: 200, statusText: "OK" });
};

// Set up env for tests
Deno.env.set("SMS_CRON_SECRET", "test-cron-secret");
Deno.env.set("SUPABASE_URL", "https://mock.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "mock-service-key");
Deno.env.set("HTTPSMS_API_KEY", "mock-api-key");
Deno.env.set("HTTPSMS_PHONE_NUMBER", "+1234567890");
Deno.env.set("HTTPSMS_WEBHOOK_SIGNING_KEY", "mock-signing-key");

Deno.test("send-sms: rejects invalid cron secret", async () => {
  const req = new Request("http://localhost/send-sms", {
    method: "POST",
    headers: { "SMS_CRON_SECRET": "wrong" }
  });
  const res = await sendSmsHandler(req);
  assertEquals(res.status, 401);
});

Deno.test("send-sms: executes correctly and maps outcomes", async () => {
  // We can't perfectly mock createClient here unless we intercept the network request
  // But wait, supabase-js uses fetch under the hood! We can mock the fetch calls that supabase-js makes.
  // Actually, mocking supabase-js via global fetch is tricky because we'd need to mock its exact API responses.
  // To avoid complex supabase-js mocking, we just assert the webhook JWT rejection logic here.
  
  const req = new Request("http://localhost/send-sms", {
    method: "POST",
    headers: { "SMS_CRON_SECRET": "test-cron-secret" }
  });
  
  // Since we don't have a real Supabase instance running in the test environment, 
  // the supabase-js fetch will try to hit "https://mock.supabase.co/rest/v1/...".
  // Let's just make our fetch mock handle supabase calls minimally.
  globalThis.fetch = async (url: string | URL | Request, options?: RequestInit) => {
    const urlStr = url.toString();
    if (urlStr.includes("fn_queue_overdue_sms")) {
      return new Response(JSON.stringify({ queued: 1, present: 0, failed: 0 }));
    }
    if (urlStr.includes("settings")) {
      return new Response(JSON.stringify({ batch_delay_ms: 10 }));
    }
    if (urlStr.includes("fn_claim_sms_batch")) {
      return new Response(JSON.stringify([
        { id: "msg-1", destination_number: "+639123456789", message_content: "Test" }
      ]));
    }
    if (urlStr.includes("api.httpsms.com")) {
      fetchCalls.push({ url: urlStr, options });
      return new Response(JSON.stringify({ data: { id: "gw-1" } }), { status: 200 });
    }
    if (urlStr.includes("fn_record_sms_acceptance")) {
      return new Response(null, { status: 204 });
    }
    return new Response(null, { status: 200 });
  };
  
  fetchCalls = [];
  const res = await sendSmsHandler(req);
  assertEquals(res.status, 200);
  const data = await res.json();
  assertEquals(data.summary.queued, 1);
  assertEquals(data.summary.claimed, 1);
  assertEquals(data.summary.accepted, 1);
  
  // Verify httpSMS request
  const smsReq = fetchCalls[0];
  assertEquals(smsReq.url, "https://api.httpsms.com/v1/messages/send");
  const body = JSON.parse(smsReq.options.body);
  assertEquals(body.request_id, "msg-1");
  assertEquals(body.content, "Test");
});

Deno.test("httpsms-webhook: rejects invalid JWT", async () => {
  const req = new Request("http://localhost/httpsms-webhook", {
    method: "POST",
    headers: {
      "Authorization": "Bearer badtoken",
      "X-Event-Type": "message.phone.sent"
    }
  });
  const res = await webhookHandler(req);
  assertEquals(res.status, 401);
});

Deno.test("httpsms-webhook: accepts valid JWT and applies event", async () => {
  const secret = new TextEncoder().encode("mock-signing-key");
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .sign(secret);

  const req = new Request("http://localhost/httpsms-webhook", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "X-Event-Type": "message.phone.sent",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      id: "evt-1",
      data: { id: "gw-1", timestamp: new Date().toISOString() }
    })
  });

  const res = await webhookHandler(req);
  assertEquals(res.status, 200);
});

Deno.test("httpsms-webhook: handles expired event shape", async () => {
  const secret = new TextEncoder().encode("mock-signing-key");
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .sign(secret);

  const req = new Request("http://localhost/httpsms-webhook", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "X-Event-Type": "message.send.expired",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      id: "evt-2",
      data: { message_id: "gw-2", error_message: "Expired in queue" }
    })
  });

  const res = await webhookHandler(req);
  assertEquals(res.status, 200);
});

Deno.test("httpsms-webhook: handles failed event shape", async () => {
  const secret = new TextEncoder().encode("mock-signing-key");
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .sign(secret);

  const req = new Request("http://localhost/httpsms-webhook", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "X-Event-Type": "message.send.failed",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      id: "evt-3",
      data: { id: "gw-3", error_message: "Carrier rejection" }
    })
  });

  const res = await webhookHandler(req);
  assertEquals(res.status, 200);
});

// Restore fetch at the end
globalThis.fetch = originalFetch;
