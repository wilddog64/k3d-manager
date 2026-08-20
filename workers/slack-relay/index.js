const ALLOWED_COMMANDS = new Set(['/cluster-up', '/cluster-down', '/cluster-status', '/cluster-diagnose', '/cluster-refresh', '/cluster-resume', '/hostinger-status', '/cleanup-stale-sandbox', '/ask', '/claude', '/gemini', '/codex', '/argocd-upgrade'])
const VALID_PROVIDERS   = new Set(['aws', 'gcp', 'az'])
const ALL_PROVIDERS     = new Set(['aws', 'gcp', 'az', 'hostinger'])
const PROVIDER_ALIASES  = { azure: 'az' }
const COMMAND_ROLES     = Object.freeze({
  '/cluster-status': 'reader',
  '/cluster-diagnose': 'reader',
  '/hostinger-status': 'reader',
  '/cluster-refresh': 'operator',
  '/cluster-up': 'admin',
  '/cluster-down': 'admin',
  '/cluster-resume': 'admin',
  '/argocd-upgrade': 'admin',
  '/cleanup-stale-sandbox': 'admin',
  '/ask': 'reader',
  '/claude': 'reader',
  '/gemini': 'reader',
  '/codex': 'reader',
})

function resolveProvider(text, dflt) {
  const t = (text || '').trim().toLowerCase()
  const p = PROVIDER_ALIASES[t] || t
  return ALL_PROVIDERS.has(p) ? p : dflt
}

function parseClusterDiagnose(text) {
  const parts = (text || '').trim().split(/\s+/).filter(Boolean)
  let target = 'hostinger'
  let index = 0
  if (parts[0] && ['hostinger', 'aws', 'gcp', 'az', 'azure', 'hub'].includes(parts[0].toLowerCase())) {
    target = parts[0].toLowerCase() === 'azure' ? 'az' : parts[0].toLowerCase()
    index = 1
  }
  const verb = parts[index] || ''
  if (!verb) {
    return { error: 'Usage: /cluster-diagnose [hostinger|aws|gcp|az|hub] <pods <namespace>|describe-pod <namespace> <pod>|logs <namespace> <pod> [container]|apps|app <name>|appsets>' }
  }
  if (verb === 'pods') {
    const namespace = parts[index + 1] || ''
    if (!namespace) return { error: 'Usage: /cluster-diagnose [provider|hub] pods <namespace>' }
    return { payload: { provider: target, action: 'get-pods', namespace } }
  }
  if (verb === 'describe-pod') {
    const namespace = parts[index + 1] || ''
    const name = parts[index + 2] || ''
    if (!namespace || !name) return { error: 'Usage: /cluster-diagnose [provider|hub] describe-pod <namespace> <pod>' }
    return { payload: { provider: target, action: 'describe-pod', namespace, name } }
  }
  if (verb === 'logs') {
    const namespace = parts[index + 1] || ''
    const name = parts[index + 2] || ''
    const container = parts[index + 3] || ''
    if (!namespace || !name) return { error: 'Usage: /cluster-diagnose [provider|hub] logs <namespace> <pod> [container]' }
    const payload = { provider: target, action: 'logs', namespace, name }
    if (container) payload.container = container
    return { payload }
  }
  if (verb === 'apps') {
    return { payload: { provider: target, action: 'get-apps' } }
  }
  if (verb === 'app') {
    const name = parts[index + 1] || ''
    if (!name) return { error: 'Usage: /cluster-diagnose [hub] app <name>' }
    return { payload: { provider: target, action: 'describe-app', name } }
  }
  if (verb === 'appsets') {
    return { payload: { provider: target, action: 'get-appsets' } }
  }
  return { error: 'Unsupported diagnostic. Use pods, describe-pod, logs, apps, app, or appsets.' }
}

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

async function relay(endpoint, payload, meta = {}) {
  try {
    const resp = await fetch(`${WEBHOOK_URL}${endpoint}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${WEBHOOK_TOKEN}`,
        'Content-Type':  'application/json',
        'X-K3DM-Role': meta.role || 'reader',
        'X-K3DM-Actor': meta.actor || 'slack:unknown',
        'X-K3DM-Source-Command': meta.sourceCommand || 'unknown',
      },
      body: JSON.stringify(payload)
    })
    if (resp.status === 409) {
      const data = await resp.json().catch(() => ({}))
      return { ok: false, conflict: data.error || 'cluster job already running' }
    }
    if (resp.status === 403) {
      const data = await resp.json().catch(() => ({}))
      return { ok: false, conflict: data.error || 'forbidden' }
    }
    return { ok: resp.ok, conflict: null }
  } catch (_) {
    return { ok: false, conflict: null }
  }
}

async function postResponseUrl(url, text, ephemeral = true) {
  if (!url) return
  const body = { text, response_type: ephemeral ? 'ephemeral' : 'in_channel' }
  await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).catch(() => {})
}

function jsonReply(text, threadTs, ephemeral = false) {
  const body = { text, response_type: ephemeral ? 'ephemeral' : 'in_channel' }
  if (threadTs && !ephemeral) body.thread_ts = threadTs
  return new Response(JSON.stringify(body),
    { status: 200, headers: { 'Content-Type': 'application/json' } })
}

addEventListener('fetch', event => {
  event.respondWith(handle(event.request, event))
})

async function handle(req, event) {
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
  const userId      = p.get('user_id')    || ''
  const userName    = p.get('user_name')  || ''
  const role        = COMMAND_ROLES[command] || 'reader'
  const actor       = userName ? `slack:${userName}${userId ? `:${userId}` : ''}` : `slack:${userId || 'unknown'}`
  const meta        = { role, actor, sourceCommand: command }

  if (!ALLOWED_COMMANDS.has(command)) return jsonReply(`Unknown command: ${command}`, threadTs)

  if (command === '/cluster-up') {
    const provider = resolveProvider(text, 'hostinger')
    const payload = { action: 'up', provider, response_url: responseUrl }
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/cluster', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict} — use /cluster-status to check progress`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    const _where = provider === 'hostinger'
      ? 'the permanent *Hostinger* app cluster'
      : `the *lab sandbox* (${provider}) — ephemeral learning sandbox`
    return jsonReply(`⏳ Bringing up ${_where}…`, threadTs, true)
  }

  if (command === '/cluster-down') {
    const provider = resolveProvider(text, 'aws')
    const payload = { action: 'down', provider, response_url: responseUrl }
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/cluster', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict} — use /cluster-status to check progress`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    const _what = provider === 'hostinger'
      ? '🛑 Tearing down the *permanent Hostinger* app cluster…'
      : '⏳ Tearing down the *lab sandbox*… — ephemeral learning sandbox only (does not affect Hostinger)'
    return jsonReply(_what, threadTs, true)
  }

  if (command === '/cluster-status') {
    const provider = resolveProvider(text, 'hostinger')
    const payload = { provider, response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/cluster-status', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    const _where = provider === 'hostinger' ? 'Hostinger' : `lab sandbox (${provider})`
    return jsonReply(`🔍 Checking ${_where} cluster status…`, threadTs, true)
  }

  if (command === '/cluster-diagnose') {
    const parsed = parseClusterDiagnose(text)
    if (parsed.error) return jsonReply(parsed.error, threadTs)
    const payload = { ...parsed.payload, response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/diagnostics', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`🔎 Running \`${parsed.payload.action}\` against *${parsed.payload.provider}*…`, threadTs, true)
  }

  if (command === '/hostinger-status') {
    const payload = { response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/hostinger-status', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply('🖥️ Checking Hostinger app cluster status…', threadTs, true)
  }

  if (command === '/cluster-refresh') {
    const provider = resolveProvider(text, 'hostinger')
    const payload = { provider, response_url: responseUrl }
    if (threadTs) payload.thread_ts = threadTs
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/cluster-refresh', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    const _msg = provider === 'hostinger'
      ? '🔄 Refreshing Hostinger kubeconfig + ArgoCD registration…'
      : '🔄 Refreshing lab sandbox credentials + tunnel…'
    return jsonReply(_msg, threadTs, true)
  }

  if (command === '/cluster-resume') {
    const provider = resolveProvider(text, '')
    if (!VALID_PROVIDERS.has(provider)) {
      return jsonReply('Usage: /cluster-resume <aws|gcp|az> — resumes a lab sandbox provision from its last checkpoint', threadTs)
    }
    const payload = { provider, response_url: responseUrl }
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/cluster-resume', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict} — use /cluster-status to check progress`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`🔄 Resuming lab sandbox provision (${provider}) from last checkpoint…`, threadTs, true)
  }

  if (command === '/cleanup-stale-sandbox') {
    const cleanupText = (text || '').trim().toLowerCase()
    if (cleanupText && !['confirm', 'apply'].includes(cleanupText)) {
      return jsonReply('Usage: /cleanup-stale-sandbox [confirm] — dry-run by default; confirm applies the cleanup', threadTs)
    }
    const confirm = ['confirm', 'apply'].includes(cleanupText)
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/cleanup-stale-sandbox', { confirm, response_url: responseUrl }, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`🧹 ${confirm ? 'Applying' : 'Previewing'} stale ACG sandbox cleanup…`, threadTs, true)
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
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/ask', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`🤖 Asking ${agent}…`, threadTs, true)
  }

  if (command === '/argocd-upgrade') {
    const parts   = text.split(/\s+/)
    const version = parts[0] || ''
    const stage   = parts[1] || 'infra'
    if (!version) return jsonReply('Usage: /argocd-upgrade <chart_version> [acg|infra]', threadTs)
    if (!['acg', 'infra'].includes(stage)) return jsonReply('stage must be acg or infra', threadTs)
    event.waitUntil((async () => {
      const { ok } = await relay('/api/v1/argocd-upgrade',
        { chart_version: version, stage, response_url: responseUrl }, meta)
      if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`⏳ Upgrading ArgoCD to chart ${version} on ${stage}…`, threadTs, true)
  }

  return jsonReply('Unhandled command', threadTs)
}
