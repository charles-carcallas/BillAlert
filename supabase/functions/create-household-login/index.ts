import { createClient } from "npm:@supabase/supabase-js@2";

// MTR-04: an Area President gives a household in their own service area a
// sign-in.
//
// Same shape as create-staff-account and reset-account-password. The
// service-role key lives only here, on the server. The rules live in the
// database (migration 12), in functions only service_role may execute.
// Business failures come back as HTTP 200 with { ok: false, kind, message }
// so the Flutter client can show the server's own plain-English message
// rather than an opaque error.

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
    return reply({ ok: false, kind: "validation", message: "The sign-in details could not be read." });
  }

  const consumerId = text(body.consumer_id).trim();
  const username = text(body.username).trim().toLowerCase();
  const password = text(body.temporary_password);

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(consumerId)) {
    return reply({ ok: false, kind: "validation", message: "Choose the household to give a sign-in." });
  }
  if (!/^[a-z][a-z0-9._-]{2,49}$/.test(username)) {
    return reply({ ok: false, kind: "validation", message: "Use a valid username with 3 to 50 letters, numbers, dots, underscores or hyphens." });
  }
  if (password.length < 8) {
    return reply({ ok: false, kind: "validation", message: "The temporary password must be at least 8 characters." });
  }

  // 1. May this Area President give this household this sign-in? Writes
  //    nothing, so an ordinary refusal leaves no auth user to clean up.
  const { data: allowed, error: checkError } = await adminClient.rpc(
    "fn_check_household_login",
    { p_admin_id: userData.user.id, p_consumer_id: consumerId, p_username: username },
  );

  if (checkError) {
    const isRule = checkError.code === "P0001";
    return reply({
      ok: false,
      kind: isRule ? "conflict" : "server",
      message: isRule
        ? sentence(checkError.message)
        : "Household sign-ins are not available on the server yet. Please try again later.",
    });
  }

  const household = Array.isArray(allowed) ? allowed[0] : null;
  if (!household) {
    return reply({ ok: false, kind: "conflict", message: "That household was not found." });
  }

  // 2. The auth user. This synthetic email contract matches
  //    AuthRepositoryImpl. It never needs a mailbox because the Area
  //    President hands the temporary password over in person.
  const email = `${username}@billalert.local`;
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (createError || !created.user) {
    const duplicate = createError?.message.toLowerCase().includes("already") ?? false;
    const weak = (createError as { code?: string } | null)?.code === "weak_password";
    return reply({
      ok: false,
      kind: duplicate ? "conflict" : weak ? "validation" : "server",
      message: duplicate
        ? `Username ${username} is already taken.`
        : weak
        ? "That temporary password is too weak. Choose a longer one."
        : "The sign-in could not be created. Please try again.",
    });
  }

  // 3. The profile, linked to the household, in one transaction. The rules
  //    are checked again there, because the household may have been given a
  //    sign-in since step 1.
  const { data: userCode, error: linkError } = await adminClient.rpc(
    "fn_create_household_login",
    {
      p_admin_id: userData.user.id,
      p_user_id: created.user.id,
      p_consumer_id: consumerId,
      p_username: username,
    },
  );

  if (linkError) {
    const rollback = await adminClient.auth.admin.deleteUser(created.user.id);
    if (rollback.error) {
      console.error("Could not roll back auth user", created.user.id, rollback.error.message);
    }

    const isRule = linkError.code === "P0001";
    return reply({
      ok: false,
      kind: isRule ? "conflict" : "server",
      message: isRule
        ? sentence(linkError.message)
        : "The household sign-in could not be created. No usable account was kept.",
    });
  }

  return reply({
    ok: true,
    id: created.user.id,
    username,
    user_code: userCode,
  }, 201);
});
