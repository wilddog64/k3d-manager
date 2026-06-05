const ALLOWED_COMMANDS = new Set(['/acg-up', '/acg-down', '/acg-status', '/argocd-upgrade'])
const VALID_PROVIDERS   = new Set(['aws', 'gcp', 'azure'])

async function verifySlack(request, body) {
  const ts  = request.headers.get('X-Slack-Request-Timestamp') || ''
  const sig = request.headers.get('X-Slack-Signature') || ''
  if (!ts || !sig) return false
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false

  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(SLACK_SIGNING_SECRET),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  )
  const raw = await crypto.subtle.sign('HMAC', key, enc.encode(`v0:${ts}:${body}`))
  const hex = Array.from(new Uint8Array(raw)).map(b => b.toString(16).padStart(2, '0')).join('')
  const expected = `v0=${hex}`
  if (expected.length !== sig.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i)
  return diff === 0
}

async function relay(endpoint, payload) {
  try {
    const resp = await fetch(`${WEBHOOK_URL}${endpoint}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${WEBHOOK_TOKEN}`,
        'Content-Type':  'application/json'
      },
      body: JSON.stringify(payload)
    })
    if (resp.status === 409) {
      const data = await resp.json().catch(() => ({}))
      return { ok: false, conflict: data.error || 'cluster job already running' }
    }
    return { ok: resp.ok, conflict: null }
  } catch (_) {
    return { ok: false, conflict: null }
  }
}

function jsonReply(text) {
  return new Response(JSON.stringify({ text, response_type: 'in_channel' }),
    { status: 200, headers: { 'Content-Type': 'application/json' } })
}

addEventListener('fetch', event => {
  event.respondWith(handle(event.request))
})

async function handle(req) {
  if (req.method !== 'POST') return new Response('Not Found', { status: 404 })

  if (new URL(req.url).pathname === '/slack/events') {
    const body = await req.text()
    if (!await verifySlack(req, body)) return new Response('Unauthorized', { status: 401 })
    const upstream = await fetch(`${WEBHOOK_URL}/slack/events`, {
      method: 'POST',
      headers: {
        'Content-Type': req.headers.get('Content-Type') || 'application/json',
        'X-Slack-Request-Timestamp': req.headers.get('X-Slack-Request-Timestamp') || '',
        'X-Slack-Signature': req.headers.get('X-Slack-Signature') || '',
      },
      body,
    })
    const text = await upstream.text()
    return new Response(text, {
      status: upstream.status,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const body = await req.text()
  if (!await verifySlack(req, body)) return new Response('Unauthorized', { status: 401 })

  const p           = new URLSearchParams(body)
  const command     = p.get('command')    || ''
  const text        = (p.get('text')      || '').trim()
  const responseUrl = p.get('response_url') || ''
  const threadTs    = p.get('thread_ts')  || ''

  if (!ALLOWED_COMMANDS.has(command)) return jsonReply(`Unknown command: ${command}`)

  if (command === '/acg-up') {
    const provider = VALID_PROVIDERS.has(text) ? text : 'aws'
    const { ok, conflict } = await relay('/api/v1/cluster', { action: 'up', provider, response_url: responseUrl })
    if (conflict) return jsonReply(`⚠️ ${conflict} — use /acg-status to check progress`)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment')
    return jsonReply(`⏳ Bringing up ACG cluster (${provider})…`)
  }

  if (command === '/acg-down') {
    const { ok, conflict } = await relay('/api/v1/cluster', { action: 'down', response_url: responseUrl })
    if (conflict) return jsonReply(`⚠️ ${conflict} — use /acg-status to check progress`)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment')
    return jsonReply('⏳ Tearing down ACG cluster…')
  }

  if (command === '/acg-status') {
    const payload = { response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    const { ok } = await relay('/api/v1/cluster-status', payload)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment')
    return jsonReply('🔍 Checking ACG cluster status…')
  }

  if (command === '/argocd-upgrade') {
    const parts   = text.split(/\s+/)
    const version = parts[0] || ''
    const stage   = parts[1] || 'infra'
    if (!version) return jsonReply('Usage: /argocd-upgrade <chart_version> [acg|infra]')
    if (!['acg', 'infra'].includes(stage)) return jsonReply('stage must be acg or infra')
    const { ok } = await relay('/api/v1/argocd-upgrade',
      { chart_version: version, stage, response_url: responseUrl })
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment')
    return jsonReply(`⏳ Upgrading ArgoCD to chart ${version} on ${stage}…`)
  }

  return jsonReply('Unhandled command')
}
