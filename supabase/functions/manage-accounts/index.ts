import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { handler, type Dependencies } from './handler.ts';

export function dependencies(): Dependencies {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Missing server configuration');
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return {
    uuid: () => crypto.randomUUID(),
    actor: async (token) => {
      const { data, error } = await client.auth.getUser(token);
      return error ? null : data.user?.id ?? null;
    },
    activeAdmin: async (id) => {
      const { data, error } = await client.from('profiles')
        .select('role,area_id,account_status,staff_enabled').eq('id', id).maybeSingle();
      if (error) throw error;
      return data?.role === 'admin' && data?.account_status === 'active' &&
        data?.staff_enabled === true && !!data?.area_id;
    },
    create: async (id, email, password) => {
      const { data, error } = await client.auth.admin.createUser({ id, email, password, email_confirm: true });
      return { data: data.user ? { id: data.user.id } : null, error };
    },
    prepare: async (name, params) => {
      const { data, error } = await client.rpc(name, params);
      return { data, error };
    },
    remove: (id) => client.auth.admin.deleteUser(id),
    manageLogin: async (token, target, action, reason) => {
      const caller = createClient(url, key, {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await caller.rpc('fn_manage_account', {
        p_target: target, p_action: action, p_reason: reason, p_reconciled: false,
      });
      return { data, error };
    },
    ban: (id, enabled) => client.auth.admin.updateUserById(id, { ban_duration: enabled ? '876000h' : 'none' }),
  };
}
if (import.meta.main) Deno.serve((request) => {
  try { return handler(request, dependencies()); }
  catch { return Response.json({ ok: false, message: 'Server configuration is incomplete.' }, { status: 503 }); }
});
