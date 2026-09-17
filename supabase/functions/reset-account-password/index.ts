import { createClient } from "npm:@supabase/supabase-js@2";

// An Area President resets a forgotten password in their own service area.
//
// Same shape as create-staff-account. The service-role key lives only here,
// on the server. The rules live in the database (migration 11), in functions
// only service_role may execute. Business failures come back as HTTP 200
// with { ok: false, kind, message } so the Flutter client can show the
// server's own plain-English message rather than an opaque error.
//
// Setting the password here ALSO ends every session the account has open:
// Supabase Auth's admin update calls User.UpdatePassword with no session,
// which logs the user out everywhere. A phone still holding a short-lived
// access token can read data for up to an hour, but any Auth call, such as
// changing the password, fails with session_not_found. The app answers that
// by signing the phone out and telling the person to sign in again.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

function reply(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/// Postgres RAISE EXCEPTION arrives with SQLSTATE P0001. Only those messages
/// were written for people; anything else is a fault, not a rule.
function sentence(message: string): string {
  return message.replace(/\.?$/, ".");
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return reply({ ok: false, kind: "validation", message: "Use POST." }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return reply({ ok: false, kind: "permission", message: "Sign in first." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return reply({ ok: false, kind: "server", message: "Server configuration is incomplete." }, 500);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return reply({ ok: false, kind: "permission", message: "Your session has expired. Sign in again." }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return reply({ ok: false, kind: "validation", message: "The reset details could not be read." });
  }

  const targetId = text(body.profile_id).trim();
  const password = text(body.temporary_password);

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(targetId)) {
    return reply({ ok: false, kind: "validation", message: "Choose the account to reset." });
  }
  if (password.length < 8) {
    return reply({ ok: false, kind: "validation", message: "The temporary password must be at least 8 characters." });
  }

  // 1. May this Area President reset this account? Writes nothing.
  const { data: allowed, error: authorizeError } = await adminClient.rpc(
    "fn_authorize_password_reset",
    { p_admin_id: userData.user.id, p_target_id: targetId },
  );

  if (authorizeError) {
    const isRule = authorizeError.code === "P0001";
    return reply({
      ok: false,
      kind: isRule ? "permission" : "server",
      message: isRule
        ? sentence(authorizeError.message)
        : "Password reset is not available on the server yet. Please try again later.",
    });
  }

  const target = Array.isArray(allowed) ? allowed[0] : null;
  if (!target) {
    return reply({ ok: false, kind: "permission", message: "That account was not found." });
  }

  // 2. Require a new password at next sign-in BEFORE changing the password.
  //    If step 3 then fails, the worst outcome is being asked to choose a new
  //    password next time. The other order could leave a temporary password
  //    that the Area President knows and that nobody is made to replace.
  const { error: flagError } = await adminClient.rpc(
    "fn_require_password_change",
    { p_admin_id: userData.user.id, p_target_id: targetId },
  );

  if (flagError) {
    return reply({ ok: false, kind: "server", message: "The password was not changed. Please try again." });
  }

  // 3. The password itself.
  const { error: updateError } = await adminClient.auth.admin.updateUserById(
    targetId,
    { password },
  );

  if (updateError) {
    const weak = (updateError as { code?: string }).code === "weak_password";
    return reply({
      ok: false,
      kind: weak ? "validation" : "server",
      message: weak
        ? "That temporary password is too weak. Choose a longer one."
        : "The password could not be reset. Please try again.",
    });
  }

  return reply({
    ok: true,
    first_name: target.target_first_name,
    last_name: target.target_last_name,
    account_kind: target.target_kind,
  });
});
