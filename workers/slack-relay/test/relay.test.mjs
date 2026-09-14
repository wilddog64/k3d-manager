import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import { createHmac, webcrypto } from 'node:crypto'

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8')
const token = 'd'.repeat(40)
const value = 'r2-0123abcd|0123456789abcdef'

function fakeKv() {
  const values = new Map()
  const puts = []
  return {
    values, puts,
    async put(key, entry, opts) { values.set(key, entry); puts.push({ key, opts }) },
    async get(key) { return values.get(key) || null },
    async delete(key) { values.delete(key) },
    async list({ prefix }) {
      return { keys: [...values.keys()].filter(key => key.startsWith(prefix)).map(name => ({ name })), list_complete: true }
    },
  }
}

function loadWorker(overrides = {}) {
  let listener
  const fetches = []
  const sandbox = {
    addEventListener(type, fn) { if (type === 'fetch') listener = fn },
    fetch: async (url, init) => { fetches.push({ url, init }); return new Response('{}', { status: 200 }) },
    crypto: webcrypto, TextEncoder, URL, URLSearchParams, Request, Response, Headers, console,
    SLACK_SIGNING_SECRET: 'test-signing-secret', WEBHOOK_URL: 'https://webhook.test', WEBHOOK_TOKEN: 'wt',
  }
  for (const [key, entry] of Object.entries(overrides)) if (entry !== undefined) sandbox[key] = entry
  vm.runInContext(source, vm.createContext(sandbox))
  return {
    fetches, kv: sandbox.APPROVALS_KV,
    async dispatch(request) {
      const ev = { request, waits: [], respondWith(promise) { this.resp = promise }, waitUntil(promise) { this.waits.push(promise) } }
      listener(ev)
      const response = await ev.resp
      await Promise.all(ev.waits)
      return response
    },
  }
}

function signed(path, body) {
  const ts = String(Math.floor(Date.now() / 1000))
  const signature = createHmac('sha256', 'test-signing-secret').update(`v0:${ts}:${body}`).digest('hex')
  return new Request(`https://relay.test${path}`, { method: 'POST', body, headers: {
    'X-Slack-Request-Timestamp': ts, 'X-Slack-Signature': `v0=${signature}`,
  } })
}

function interactivityBody(userId, actionId, actionValue) {
  return 'payload=' + encodeURIComponent(JSON.stringify({ type: 'block_actions', user: { id: userId },
    response_url: 'https://hooks.slack.test/resp', actions: [{ action_id: actionId, value: actionValue }] }))
}

test('drain requires an authorized bearer', async () => {
  const worker = loadWorker({ APPROVALS_KV: fakeKv(), APPROVAL_DRAIN_TOKEN: token })
  for (const auth of [undefined, 'Bearer wrong']) {
    const headers = auth ? { Authorization: auth } : {}
    assert.equal((await worker.dispatch(new Request('https://relay.test/hermes/approvals', { headers }))).status, 401)
  }
})

test('drain rejects short tokens and missing KV', async () => {
  let worker = loadWorker({ APPROVALS_KV: fakeKv(), APPROVAL_DRAIN_TOKEN: 'short' })
  assert.equal((await worker.dispatch(new Request('https://relay.test/hermes/approvals', { headers: { Authorization: 'Bearer short' } }))).status, 401)
  worker = loadWorker({ APPROVAL_DRAIN_TOKEN: token, APPROVALS_KV: undefined })
  assert.equal((await worker.dispatch(new Request('https://relay.test/hermes/approvals', { headers: { Authorization: `Bearer ${token}` } }))).status, 503)
})

test('drain requires a configured KV namespace', async () => {
  const worker = loadWorker({ APPROVAL_DRAIN_TOKEN: token, APPROVALS_KV: undefined })
  const response = await worker.dispatch(new Request('https://relay.test/hermes/approvals', { headers: { Authorization: `Bearer ${token}` } }))
  assert.equal(response.status, 503)
})

test('drain lists and deletes approvals', async () => {
  const kv = fakeKv()
  await kv.put('approval:r2-0123abcd', JSON.stringify({ approved_by: 'UAPPROVER1', approved_at: 1, nonce: '0123456789abcdef' }))
  await kv.put('reauth:UAPPROVER1', '1')
  const worker = loadWorker({ APPROVALS_KV: kv, APPROVAL_DRAIN_TOKEN: token })
  const headers = { Authorization: `Bearer ${token}` }
  const listed = await worker.dispatch(new Request('https://relay.test/hermes/approvals', { headers }))
  const items = await listed.json()
  assert.equal(listed.status, 200); assert.equal(items.length, 1); assert.equal(items[0].action_id, 'r2-0123abcd'); assert.equal(items[0].nonce, '0123456789abcdef')
  assert.equal((await worker.dispatch(new Request('https://relay.test/hermes/approvals/r2-0123abcd', { method: 'DELETE', headers }))).status, 204)
  assert.equal(await kv.get('approval:r2-0123abcd'), null)
  assert.equal((await worker.dispatch(new Request('https://relay.test/hermes/approvals/bad%2Fid', { method: 'DELETE', headers }))).status, 404)
})

test('interactivity rejects bad signatures without side effects', async () => {
  const kv = fakeKv(); const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  const response = await worker.dispatch(new Request('https://relay.test/slack/interactivity', { method: 'POST', body: interactivityBody('UAPPROVER1', 'hermes_approve', value) }))
  assert.equal(response.status, 401); assert.equal(kv.puts.length, 0); assert.equal(worker.fetches.length, 0)
})

test('non-allowlisted user cannot approve', async () => {
  const kv = fakeKv(); const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  assert.equal((await worker.dispatch(signed('/slack/interactivity', interactivityBody('UOTHER', 'hermes_approve', value)))).status, 200)
  assert.equal(await kv.get('approval:r2-0123abcd'), null)
  assert.match(worker.fetches.find(item => item.url.includes('hooks.slack.test')).init.body, /not authorized/)
})

test('allowlisted user must re-authenticate', async () => {
  const kv = fakeKv(); const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  await worker.dispatch(signed('/slack/interactivity', interactivityBody('UAPPROVER1', 'hermes_approve', value)))
  assert.equal(await kv.get('approval:r2-0123abcd'), null)
  assert.match(worker.fetches[0].init.body, /hermes-auth/)
})

test('happy approve stores an expiring approval and replaces the message', async () => {
  const kv = fakeKv(); await kv.put('reauth:UAPPROVER1', '1')
  const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  await worker.dispatch(signed('/slack/interactivity', interactivityBody('UAPPROVER1', 'hermes_approve', value)))
  const approval = JSON.parse(await kv.get('approval:r2-0123abcd'))
  assert.equal(approval.nonce, '0123456789abcdef'); assert.equal(approval.approved_by, 'UAPPROVER1')
  assert.equal(kv.puts.at(-1).opts.expirationTtl, 3600)
  assert.match(worker.fetches[0].init.body, /replace_original.*true/); assert.match(worker.fetches[0].init.body, /approved by/)
})

test('deny dismisses without recording an approval', async () => {
  const kv = fakeKv(); await kv.put('reauth:UAPPROVER1', '1')
  const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  await worker.dispatch(signed('/slack/interactivity', interactivityBody('UAPPROVER1', 'hermes_deny', value)))
  assert.equal(await kv.get('approval:r2-0123abcd'), null); assert.match(worker.fetches[0].init.body, /denied/)
})

test('DELETE rejects encoded path separators', async () => {
  const worker = loadWorker({ APPROVALS_KV: fakeKv(), APPROVAL_DRAIN_TOKEN: token })
  const response = await worker.dispatch(new Request('https://relay.test/hermes/approvals/bad%2Fid', { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } }))
  assert.equal(response.status, 404)
})

test('malformed interactivity values are ignored', async () => {
  for (const malformed of ['r2-0123abcd', 'rm -rf|0123456789abcdef']) {
    const kv = fakeKv(); const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
    assert.equal((await worker.dispatch(signed('/slack/interactivity', interactivityBody('UAPPROVER1', 'hermes_approve', malformed)))).status, 200)
    assert.equal(kv.puts.length, 0); assert.equal(worker.fetches.length, 0)
  }
})

test('/hermes-auth grants allowlisted users a 24h re-auth', async () => {
  const kv = fakeKv(); const worker = loadWorker({ APPROVALS_KV: kv, APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  const body = 'command=/hermes-auth&user_id=UAPPROVER1&response_url=https%3A%2F%2Fhooks.slack.test%2Fresp'
  const response = await worker.dispatch(signed('/slack/commands', body))
  assert.equal(kv.puts[0].opts.expirationTtl, 86400); assert.match(await response.text(), /Re-authenticated/)
  const denied = await worker.dispatch(signed('/slack/commands', body.replace('UAPPROVER1', 'UOTHER')))
  assert.equal(kv.puts.length, 1); assert.match(await denied.text(), /not authorized/)
})

test('cluster-status still relays and events GET is missing', async () => {
  const worker = loadWorker({ APPROVALS_KV: fakeKv(), APPROVER_ALLOWLIST: 'UAPPROVER1,UAPPROVER2', APPROVAL_DRAIN_TOKEN: token })
  await worker.dispatch(signed('/slack/commands', 'command=/cluster-status&user_id=UAPPROVER1&response_url=https%3A%2F%2Fhooks.slack.test%2Fresp'))
  assert.ok(worker.fetches.some(item => item.url === 'https://webhook.test/api/v1/cluster-status'))
  assert.equal((await worker.dispatch(new Request('https://relay.test/slack/events'))).status, 404)
})

test('GET /slack/events returns 404', async () => {
  const worker = loadWorker()
  assert.equal((await worker.dispatch(new Request('https://relay.test/slack/events'))).status, 404)
})
