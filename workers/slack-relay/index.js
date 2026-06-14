const ALLOWED_COMMANDS = new Set(['/cluster-up', '/cluster-down', '/cluster-status', '/cluster-refresh', '/cluster-resume', '/hostinger-status', '/ask', '/claude', '/gemini', '/codex', '/argocd-upgrade'])
const VALID_PROVIDERS   = new Set(['aws', 'gcp', 'az'])
const PROVIDER_ALIASES  = { azure: 'az' }

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

function jsonReply(text, threadTs, ephemeral = false) {
  const body = { text, response_type: ephemeral ? 'ephemeral' : 'in_channel' }
  if (threadTs && !ephemeral) body.thread_ts = threadTs
  return new Response(JSON.stringify(body),
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

  if (!ALLOWED_COMMANDS.has(command)) return jsonReply(`Unknown command: ${command}`, threadTs)

  if (command === '/cluster-up') {
    const _t = text.toLowerCase()
    const _p = PROVIDER_ALIASES[_t] || _t
    const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
    const { ok, conflict } = await relay('/api/v1/cluster', { action: 'up', provider, response_url: responseUrl })
    if (conflict) return jsonReply(`⚠️ ${conflict} — use /cluster-status to check progress`, threadTs)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply(`⏳ Bringing up the *lab sandbox* (${provider})… — ephemeral learning sandbox only; the permanent app cluster is Hostinger (use /hostinger-status)`, threadTs, true)
  }

  if (command === '/cluster-down') {
    const { ok, conflict } = await relay('/api/v1/cluster', { action: 'down', response_url: responseUrl })
    if (conflict) return jsonReply(`⚠️ ${conflict} — use /cluster-status to check progress`, threadTs)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply('⏳ Tearing down the *lab sandbox*… — ephemeral learning sandbox only (does not affect the permanent Hostinger app cluster)', threadTs, true)
  }

  if (command === '/cluster-status') {
    const payload = { response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    const { ok } = await relay('/api/v1/cluster-status', payload)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply('🔍 Checking lab sandbox cluster status…', threadTs, true)
  }

  if (command === '/hostinger-status') {
    const payload = { response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    const { ok } = await relay('/api/v1/hostinger-status', payload)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply('🖥️ Checking Hostinger app cluster status…', threadTs, true)
  }

  if (command === '/cluster-refresh') {
    const payload = { response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    const { ok } = await relay('/api/v1/cluster-refresh', payload)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply('🔄 Refreshing lab sandbox credentials + tunnel…', threadTs, true)
  }

  if (command === '/cluster-resume') {
    const _t = text.toLowerCase()
    const _p = PROVIDER_ALIASES[_t] || _t
    const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
    const { ok, conflict } = await relay('/api/v1/cluster-resume', { provider, response_url: responseUrl })
    if (conflict) return jsonReply(`⚠️ ${conflict} — use /cluster-status to check progress`, threadTs)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply(`🔄 Resuming lab sandbox provision (${provider}) from last checkpoint…`, threadTs, true)
  }

  if (command === '/ask' || command === '/claude' || command === '/gemini' || command === '/codex') {
    const VALID_AGENTS = new Set(['claude', 'gemini', 'codex'])
    let agent, question
    if (command === '/ask') {
      const parts = text.split(/\s+/)
      agent = VALID_AGENTS.has(parts[0]) ? parts[0] : 'claude'
      question = VALID_AGENTS.has(parts[0]) ? parts.slice(1).join(' ').trim() : text
    } else {
      agent = command.slice(1)
      question = text
    }
    if (!question) return jsonReply(`Usage: ${command} <question>`, threadTs)
    const payload = { agent, question, response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    const { ok } = await relay('/api/v1/ask', payload)
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply(`🤖 Asking ${agent}…`, threadTs, true)
  }

  if (command === '/argocd-upgrade') {
    const parts   = text.split(/\s+/)
    const version = parts[0] || ''
    const stage   = parts[1] || 'infra'
    if (!version) return jsonReply('Usage: /argocd-upgrade <chart_version> [acg|infra]', threadTs)
    if (!['acg', 'infra'].includes(stage)) return jsonReply('stage must be acg or infra', threadTs)
    const { ok } = await relay('/api/v1/argocd-upgrade',
      { chart_version: version, stage, response_url: responseUrl })
    if (!ok) return jsonReply('❌ Webhook unreachable — try again in a moment', threadTs)
    return jsonReply(`⏳ Upgrading ArgoCD to chart ${version} on ${stage}…`, threadTs, true)
  }

  return jsonReply('Unhandled command', threadTs)
}
