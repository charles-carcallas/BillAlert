import { handler, type Dependencies } from '../manage-accounts/handler.ts';

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
}
const body = { action: 'create_successor', username: 'next.president', first_name: 'Next',
  last_name: 'President', temporary_password: 'temporary-test-only', reason: 'Term ended', reconciled: true, household: {mode:'new', consumer_no:'TEST-1', confirmed:true} };
function setup(overrides: Partial<Dependencies> = {}) {
  const calls: string[] = [];
  const deps: Dependencies = {
    actor: async () => 'actor', activeAdmin: async () => true, uuid: () => 'new-id',
    create: async (id) => { calls.push('create'); return { data: { id } }; },
    prepare: async (name, params) => { calls.push(name); equal(params.p_actor, 'actor'); return { data: 'transfer' }; },
    remove: async () => { calls.push('remove'); return {}; },
    manageLogin: async () => { calls.push('manageLogin'); return { data: null }; },
    ban: async () => { calls.push('ban'); return {}; }, ...overrides,
  };
  const send = (input: unknown = body, authorization = 'Bearer verified-token') => handler(new Request('https://local.invalid', {
    method: 'POST', headers: { Authorization: authorization }, body: JSON.stringify(input),
  }), deps);
  return { calls, send };
}
Deno.test('success uses verified actor and prepares disabled successor', async () => {
  const s = setup(); equal((await s.send()).status, 201);
  equal(s.calls, ['create', 'fn_create_linked_account']);
});
Deno.test('consumer identity uses separate preparation contract', async () => {
  const s = setup(); await s.send({ ...body, action: 'create_consumer_login', reconciled: false });
  equal(s.calls, ['create', 'fn_create_linked_account']);
});
Deno.test('denies candidate and missing or unverified identity before creation', async () => {
  for (const overrides of [{ activeAdmin: async () => false }, { actor: async () => null }]) {
    const s = setup(overrides); equal((await (await s.send()).json()).ok, false); equal(s.calls, []);
  }
  const s = setup(); equal((await s.send(body, '')).status, 401); equal(s.calls, []);
});
Deno.test('validates reconciliation, reason and malformed bodies before creation', async () => {
  for (const input of [{ ...body, reconciled: false }, { ...body, reconciled: 'true' },
    { ...body, reason: '' }, null, [], { ...body, action: 'disable_login' }]) {
    const s = setup(); equal((await (await s.send(input)).json()).ok, false); equal(s.calls, []);
  }
});
Deno.test('definite database rejection compensates exactly once', async () => {
  const s = setup({ prepare: async () => ({ data: null, error: { code: '23505' } }) });
  equal((await (await s.send()).json()).kind, 'rejected'); equal(s.calls, ['create', 'remove']);
});
Deno.test('ambiguous database outcomes never delete auth identity', async () => {
  for (const prepare of [async () => { throw new Error('network'); },
    async () => ({ data: null, error: { code: '', message: 'Fetch failed' } }),
    async () => ({ data: null, error: { code: 'PGRST000' } }),
    async () => ({ data: null, error: { code: '57014' } })]) {
    const s = setup({ prepare }); equal((await (await s.send()).json()).kind, 'uncertain'); equal(s.calls, ['create']);
  }
});
Deno.test('failed cleanup never claims account was removed', async () => {
  for (const remove of [async () => ({ error: 'failed' }), async () => { throw new Error('timeout'); }]) {
    const s = setup({ prepare: async () => ({ data: null, error: { code: 'P0001' } }), remove });
    const result = await (await s.send()).json(); equal(result.kind, 'uncertain'); equal(result.id, 'new-id');
    equal(result.message.includes('may remain'), true);
  }
});
Deno.test('ambiguous auth creation preserves preallocated recovery reference', async () => {
  const s = setup({ create: async () => { throw new Error('lost response'); } });
  const result = await (await s.send()).json(); equal(result.id, 'new-id'); equal(result.kind, 'uncertain'); equal(s.calls, []);
});
Deno.test('emergency suspension uses database authorization before Auth ban', async () => {
  const s = setup();
  const result = await (await s.send({ action: 'disable_login', target: '00000000-0000-4000-8000-000000000001', reason: 'Lost phone' })).json();
  equal(result.ok, true); equal(s.calls, ['manageLogin', 'ban']);
});
Deno.test('database rejection prevents banning another area or admin identity', async () => {
  const s = setup({ manageLogin: async () => ({ data: null, error: { code: 'P0001' } }) });
  equal((await (await s.send({ action: 'disable_login', target: '00000000-0000-4000-8000-000000000001', reason: 'Lost phone' })).json()).ok, false);
  equal(s.calls, []);
});
Deno.test('Auth ban failure reports partial state without claiming revocation', async () => {
  const s = setup({ ban: async () => ({ error: 'network' }) });
  const result = await (await s.send({ action: 'disable_login', target: '00000000-0000-4000-8000-000000000001', reason: 'Lost phone' })).json();
  equal(result.kind, 'uncertain'); equal(result.message.includes('not been confirmed revoked'), true);
});
Deno.test('malformed successful preparation response is uncertain without deletion', async () => {
  const s = setup({ prepare: async () => ({ data: null }) });
  equal((await (await s.send()).json()).kind, 'uncertain'); equal(s.calls, ['create']);
});

Deno.test('missing household and unconfirmed ownership never create Auth users', async () => {
 for (const household of [undefined, {}, {mode:'new',consumer_no:'T',confirmed:false}, {mode:'existing',id:'bad',confirmed:true}]) {
  const s=setup(); equal((await (await s.send({...body,household})).json()).kind,'validation'); equal(s.calls,[]);
 }
});
Deno.test('linked creation forwards actor, role and household together', async () => {
 const household={mode:'existing',id:'00000000-0000-4000-8000-000000000001',confirmed:true};
 const s=setup({prepare:async(name,params)=>{equal(name,'fn_create_linked_account');equal(params.p_actor,'actor');equal(params.p_role,'cashier');equal(params.p_household,household);return {data:'new-id'};}});
 equal((await s.send({...body,action:'create_account',role:'cashier',household})).status,201);
});

Deno.test('consumer creation cannot bypass successor reconciliation with role override', async () => {
 const s=setup();
 equal((await (await s.send({...body, action:'create_account', role:'successor', reconciled:false})).json()).kind,'validation');
 equal(s.calls,[]);
});
