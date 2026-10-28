export type Outcome<T> = { data: T; error?: { code?: string; message?: string; status?: number } | null };
export interface Dependencies {
  actor(token: string): Promise<string | null>;
  activeAdmin(actor: string): Promise<boolean>;
  uuid(): string;
  create(id: string, email: string, password: string): Promise<Outcome<{ id: string } | null>>;
  prepare(name: string, params: Record<string, unknown>): Promise<Outcome<unknown>>;
  remove(id: string): Promise<{ error?: unknown }>;
  manageLogin(token: string, target: string, action: string, reason: string): Promise<Outcome<unknown>>;
  ban(target: string, enabled: boolean): Promise<{ error?: unknown }>;
}
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
const reply = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });
const value = (v: unknown) => typeof v === 'string' ? v.trim() : '';
const uncertain = (id: string) => reply({ ok: false, kind: 'uncertain', id,
  message: `The outcome is uncertain. Do not repeat creation. Refresh accounts and transfers; ask support to check the username and reference ${id}. An authentication account may remain.` });

// Only explicit PostgreSQL transaction rejections prove no profile committed.
// Transport errors, gateway errors, timeouts and malformed replies never qualify.
export function definiteRejection(code?: string): boolean {
  return !!code && /^(P0001|42501|23505|23503|23502|23514|22023)$/.test(code);
}

export async function handler(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return reply({ ok: false, message: 'Use POST.' }, 405);
  const token = request.headers.get('Authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return reply({ ok: false, message: 'Sign in first.' }, 401);
  let actor: string | null;
  try {
    actor = await deps.actor(token);
    if (!actor) return reply({ ok: false, message: 'Sign in again.' }, 401);
    if (!await deps.activeAdmin(actor)) return reply({ ok: false, kind: 'permission',
      message: 'Only an active Area President with work access can create accounts.' });
  } catch { return reply({ ok: false, message: 'Could not verify your access. No creation was attempted.' }); }
  let body: Record<string, unknown>;
  try {
    body = await request.json();
    if (!body || Array.isArray(body) || typeof body !== 'object') throw new Error();
  } catch { return reply({ ok: false, kind: 'validation', message: 'Invalid account details.' }); }
  if (body.action === 'disable_login' || body.action === 'enable_login') {
    const target = value(body.target), reason = value(body.reason);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(target) || !reason) {
      return reply({ ok: false, kind: 'validation', message: 'Choose an account and give a reason.' });
    }
    try {
      // Caller-scoped SQL rechecks area, target and the prohibition on admins.
      const managed = await deps.manageLogin(token, target, body.action, reason);
      if (managed.error) return reply({ ok: false, kind: 'rejected',
        message: 'Login change was not confirmed. Refresh the account before trying again.' });
      const banned = await deps.ban(target, body.action === 'disable_login');
      if (banned.error) throw new Error('Auth update failed');
      return reply({ ok: true, message: body.action === 'disable_login'
        ? 'Database access blocked and Auth login banned. Existing tokens are blocked by database policy; token revocation is not claimed.'
        : 'Database login restored and Auth ban removed.' });
    } catch {
      return reply({ ok: false, kind: 'uncertain', message: 'The database login state may have changed, but the Auth ban update could not be confirmed. Refresh and ask support to check both states. Sessions have not been confirmed revoked.' });
    }
  }
  const successor = body.action === 'create_successor';
  if (!successor && !['create_account', 'create_consumer_login'].includes(String(body.action))) return reply({ ok: false, kind: 'validation', message: 'Unknown action.' });
  const household = body.household as Record<string, unknown> | undefined;
  const role = successor ? 'successor' : value(body.role) || 'consumer';
  if (!household || typeof household !== 'object' || Array.isArray(household) ||
      !['new', 'existing', 'same_household', 'handover'].includes(String(household.mode)) ||
      !(successor ? ['successor'] : ['consumer', 'meter_reader', 'cashier']).includes(role) ||
      household.confirmed !== true ||
      (['new', 'handover'].includes(String(household.mode)) && !value(household.consumer_no)) ||
      (household.mode !== 'new' && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value(household.id))) ||
      (['same_household', 'handover'].includes(String(household.mode)) && !value(household.reference))) {
    return reply({ ok: false, kind: 'validation', message: 'Select or create their own household and confirm ownership before creating an account.' });
  }
  const username = value(body.username).toLowerCase();
  const first = value(body.first_name), last = value(body.last_name), reason = value(body.reason);
  const password = typeof body.temporary_password === 'string' ? body.temporary_password : '';
  if (!/^[a-z][a-z0-9._-]{2,49}$/.test(username) || !first || !last || !reason ||
      first.length > 100 || last.length > 100 || reason.length > 2000 ||
      password.length < 8 || password.length > 256 || (successor && body.reconciled !== true)) {
    return reply({ ok: false, kind: 'validation', message: 'Enter a valid username, names, temporary password and reason. Confirm reconciliation for a successor.' });
  }
  const id = deps.uuid();
  try {
    const created = await deps.create(id, `${username}@billalert.local`, password);
    if (created.error || !created.data || created.data.id !== id) {
      if (created.error?.status && created.error.status >= 400 && created.error.status < 500) {
        return reply({ ok: false, kind: 'conflict', message: 'Authentication rejected creation. Check the username and password; if you previously received an uncertain result, ask support to check it before retrying.' });
      }
      return uncertain(id);
    }
    const result = await deps.prepare('fn_create_linked_account', {
      p_actor: actor, p_user: id, p_role: role, p_household: household,
      p_username: username, p_first_name: first, p_last_name: last, p_reason: reason,
    });
    if (result.error) {
      if (!definiteRejection(result.error.code)) return uncertain(id);
      try {
        const cleanup = await deps.remove(id);
        if (cleanup.error) return uncertain(id);
      } catch { return uncertain(id); }
      return reply({ ok: false, kind: 'rejected', message: 'The database rejected this account setup. The newly created authentication account was removed. Refresh and review the current assignments before trying again.' });
    }
    // Both preparation contracts return a UUID. A missing/malformed success
    // payload is not proof of failure and must not trigger compensation.
    if (typeof result.data !== 'string' || !result.data) return uncertain(id);
    return reply({ ok: true, id, result: result.data }, 201);
  } catch { return uncertain(id); }
}
