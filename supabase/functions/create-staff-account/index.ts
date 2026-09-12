import { createClient } from "npm:@supabase/supabase-js@2";

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

  const { data: profile, error: profileError } = await callerClient
    .from("profiles")
    .select("id, role, area_id, account_status")
    .eq("id", userData.user.id)
    .maybeSingle();

  if (
    profileError || !profile || profile.role !== "admin" ||
    profile.account_status !== "active" || !profile.area_id
  ) {
    // Business failures use a successful HTTP response so the Flutter client
    // can read the safe, specific message instead of receiving an opaque
    // FunctionsHttpError for every non-2xx status.
    return reply({ ok: false, kind: "permission", message: "Only an active Area President can create a staff account." });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return reply({ ok: false, kind: "validation", message: "The account details could not be read." });
  }

  const username = text(body.username).trim().toLowerCase();
  const firstName = text(body.first_name).trim();
  const lastName = text(body.last_name).trim();
  const role = text(body.role);
  const password = text(body.temporary_password);
  const contactNumber = text(body.contact_number);

  if (!/^[a-z][a-z0-9._-]{2,49}$/.test(username)) {
    return reply({ ok: false, kind: "validation", message: "Use a valid username with 3 to 50 letters, numbers, dots, underscores or hyphens." });
  }
  if (!firstName || !lastName) {
    return reply({ ok: false, kind: "validation", message: "Enter the staff member's first and last name." });
  }
  if (role !== "meter_reader" && role !== "cashier") {
    return reply({ ok: false, kind: "validation", message: "A staff account must be a Meter Reader or Cashier." });
  }
  if (password.length < 8) {
    return reply({ ok: false, kind: "validation", message: "The temporary password must be at least 8 characters." });
  }

  // This synthetic email contract matches AuthRepositoryImpl. It never needs
  // a mailbox because the Area President confirms the account in person.
  const email = `${username}@billalert.local`;
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (createError || !created.user) {
    const duplicate = createError?.message.toLowerCase().includes("already") ?? false;
    return reply({
      ok: false,
      kind: duplicate ? "conflict" : "server",
      message: duplicate
        ? `Username ${username} is already taken.`
        : "The authentication account could not be created. Please try again.",
    });
  }

  const { data: userCode, error: profileCreateError } = await adminClient.rpc(
    "fn_create_staff_profile",
    {
      p_admin_id: userData.user.id,
      p_user_id: created.user.id,
      p_username: username,
      p_first_name: firstName,
      p_last_name: lastName,
      p_role: role,
      p_contact_number: contactNumber || null,
    },
  );

  if (profileCreateError) {
    const rollback = await adminClient.auth.admin.deleteUser(created.user.id);
    if (rollback.error) {
      console.error("Could not roll back auth user", created.user.id, rollback.error.message);
    }

    const message = profileCreateError.message;
    const isExpected = message.startsWith("Assignment blocked") ||
      message.startsWith("Username ") ||
      message.startsWith("That username or staff assignment");
    return reply({
      ok: false,
      kind: isExpected ? "conflict" : "server",
      message: isExpected
        ? message.replace(/\.?$/, ".")
        : "The staff profile could not be created. No usable account was kept.",
    });
  }

  return reply({
    ok: true,
    id: created.user.id,
    user_code: userCode,
  }, 201);
});
