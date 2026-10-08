const ALLOWED_COMMANDS = new Set(['/cluster-up', '/cluster-down', '/cluster-status', '/cluster-diagnose', '/cluster-refresh', '/cluster-resume', '/hostinger-status', '/cleanup-stale-sandbox', '/ask', '/ask-docs', '/claude', '/gemini', '/codex', '/argocd-upgrade', '/hermes-auth', '/k3dm'])
const APPROVAL_TTL_SECONDS = 3600
const REAUTH_TTL_SECONDS   = 86400
const HERMES_ACTION_ID_RE  = /^r[0-9]+-[0-9a-f]{8}$/
const HERMES_NONCE_RE      = /^[0-9a-f]{16}$/
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
  '/hermes-auth': 'admin',
  '/ask': 'reader',
  '/ask-docs': 'reader',
  '/claude': 'reader',
  '/gemini': 'reader',
  '/codex': 'reader',
  '/k3dm': 'admin',
})

function resolveProvider(text, dflt) {
  const t = (text || '').trim().toLowerCase()
  const p = PROVIDER_ALIASES[t] || t
  return ALL_PROVIDERS.has(p) ? p : dflt
}

function resolveProviderStrict(text) {
  const t = (text || '').trim().toLowerCase()
  if (!t) return { error: 'no cluster named' }
  const p = PROVIDER_ALIASES[t] || t
  if (!ALL_PROVIDERS.has(p)) return { error: `unknown cluster \`${t}\`` }
  return { provider: p }
}

const CLUSTER_ARG_USAGE = '`hostinger` is the permanent app cluster; `aws`, `gcp` and `az` are ephemeral lab sandboxes.'
const K3DM_USAGE = [
  'Usage: /k3dm <target> [KEY=value …] [confirm]',
  'Examples: /k3dm help · /k3dm status · /k3dm test-all',
  'Use `/k3dm help` to see targets allowed for your role.',
].join('\n')
const CLUSTER_RESUME_USAGE = [
  'Usage: /cluster-resume <cluster>',
  'Clusters: aws, gcp, az',
  'Example: /cluster-resume aws',
  'Resumes a lab sandbox from its last checkpoint.',
].join('\n')
const CLEANUP_USAGE = [
  'Usage: /cleanup-stale-sandbox [preview|confirm|apply]',
  'Examples: /cleanup-stale-sandbox preview · /cleanup-stale-sandbox apply',
  'Preview reports local ACG connection cleanup only: launchd agents, plist files, and the kube context.',
  '`confirm` or `apply` performs the local cleanup; it does not terminate AWS or delete workloads.',
].join('\n')
const ASK_DOCS_USAGE = [
  'Usage: /ask-docs [--sources] <question>',
  'Examples: /ask-docs how does test-all publish metrics?',
  '/ask-docs --sources where is the webhook status documented?',
].join('\n')
const ARGOCD_UPGRADE_USAGE = [
  'Usage: /argocd-upgrade <chart-version> [acg|infra]',
  'Examples: /argocd-upgrade 7.9.1 infra · /argocd-upgrade 7.9.1 acg',
].join('\n')
const CLUSTER_DIAGNOSE_USAGE = [
  'Usage: /cluster-diagnose [cluster] <request>',
  'Clusters: hostinger, aws, gcp, az, hub (default: hostinger)',
  'All pods: /cluster-diagnose hub',
  'List pods: /cluster-diagnose hub pods <namespace>',
  'Describe pod: /cluster-diagnose hub pod <namespace> <pod>',
  'Pod logs: /cluster-diagnose hub logs <namespace> <pod> [container]',
  'Applications: /cluster-diagnose hub apps | app <name> | appsets',
].join('\n')

function parseClusterDiagnose(text) {
  const parts = (text || '').trim().split(/\s+/).filter(Boolean)
  let target = 'hostinger'
  let index = 0
  if (parts[0] && ['hostinger', 'aws', 'gcp', 'az', 'azure', 'hub'].includes(parts[0].toLowerCase())) {
    target = parts[0].toLowerCase() === 'azure' ? 'az' : parts[0].toLowerCase()
    index = 1
  }
  const verb = parts[index] || ''
  if (!verb && index === 1) {
    return { payload: { provider: target, action: 'get-pods-all' } }
  }
  if (!verb) {
    return { error: CLUSTER_DIAGNOSE_USAGE }
  }
  const namespaceFirst = !['pods', 'describe-pod', 'logs', 'apps', 'app', 'appsets'].includes(verb) &&
    ['pod', 'describe-pod', 'logs'].includes(parts[index + 1])
  if (namespaceFirst) {
    index += 1
  }
  const diagnosticVerb = (namespaceFirst ? parts[index] : verb) === 'pod'
    ? 'describe-pod' : (namespaceFirst ? parts[index] : verb)
  if (diagnosticVerb === 'pods') {
    const namespace = namespaceFirst ? parts[index - 1] : parts[index + 1]
    if (!namespace) return { error: 'Usage: /cluster-diagnose [provider|hub] pods <namespace>' }
    return { payload: { provider: target, action: 'get-pods', namespace } }
  }
  if (diagnosticVerb === 'describe-pod') {
    const namespace = namespaceFirst ? parts[index - 1] : parts[index + 1]
    const name = namespaceFirst ? parts[index + 1] : parts[index + 2]
    if (!namespace || !name) return { error: 'Usage: /cluster-diagnose [provider|hub] describe-pod <namespace> <pod>' }
    return { payload: { provider: target, action: 'describe-pod', namespace, name } }
  }
  if (diagnosticVerb === 'logs') {
    const namespace = namespaceFirst ? parts[index - 1] : parts[index + 1]
    const name = namespaceFirst ? parts[index + 1] : parts[index + 2]
    const container = namespaceFirst ? parts[index + 2] : parts[index + 3]
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
  return { error: `${CLUSTER_DIAGNOSE_USAGE}\nUnknown request: ${verb}` }
}

const K3DM_FREE_TEXT_KEYS = new Set(['Q'])

function parseK3dm(text) {
  const parts = (text || '').trim().split(/\s+/).filter(Boolean)
  const target = (parts.shift() || 'help').toLowerCase()
  if (!/^[a-z][a-z0-9-]{0,40}$/.test(target)) return { error: K3DM_USAGE }
  const args = {}
  let confirm = false
  let freeKey = null
  for (const part of parts) {
    if (part.toLowerCase() === 'confirm') { confirm = true; freeKey = null; continue }
    const m = /^([A-Z][A-Z_]{0,31})=(\S{1,256})$/.exec(part)
    if (m) {
      args[m[1]] = m[2]
      freeKey = K3DM_FREE_TEXT_KEYS.has(m[1]) ? m[1] : null
      continue
    }
    if (!freeKey || args[freeKey].length + 1 + part.length > 256) return { error: K3DM_USAGE }
    args[freeKey] += ' ' + part
  }
  return { payload: { target, args, confirm } }
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

function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

function approvalsKv() {
  return typeof APPROVALS_KV === 'undefined' ? null : APPROVALS_KV
}

function approverAllowed(userId) {
  const raw = typeof APPROVER_ALLOWLIST === 'undefined' ? '' : String(APPROVER_ALLOWLIST)
  return !!userId && raw.split(',').map(s => s.trim()).filter(Boolean).includes(userId)
}

function drainAuthorized(req) {
  const token = typeof APPROVAL_DRAIN_TOKEN === 'undefined' ? '' : String(APPROVAL_DRAIN_TOKEN)
  if (token.length < 32) return false
  return constantTimeEqual(req.headers.get('Authorization') || '', `Bearer ${token}`)
}

async function handleDrain(req, pathname) {
  if (!drainAuthorized(req)) return new Response('Unauthorized', { status: 401 })
  const kv = approvalsKv()
  if (!kv) return new Response('Approvals not configured', { status: 503 })
  if (req.method === 'GET' && pathname === '/hermes/approvals') {
    const listed = await kv.list({ prefix: 'approval:', limit: 50 })
    const items = []
    for (const key of listed.keys || []) {
      const raw = await kv.get(key.name)
      if (!raw) continue
      let value
      try { value = JSON.parse(raw) } catch (_) { continue }
      items.push({
        action_id: key.name.slice('approval:'.length),
        approved_by: String(value.approved_by || ''),
        approved_at: Number(value.approved_at || 0),
        nonce: String(value.nonce || ''),
      })
    }
    return new Response(JSON.stringify(items), { status: 200, headers: { 'Content-Type': 'application/json' } })
  }
  const match = pathname.match(/^\/hermes\/approvals\/([A-Za-z0-9-]{1,64})$/)
  if (req.method === 'DELETE' && match) {
    await kv.delete(`approval:${match[1]}`)
    return new Response(null, { status: 204 })
  }
  return new Response('Not Found', { status: 404 })
}

async function handleInteractivity(req, event) {
  const body = await req.text()
  if (!await verifySlack(req, body)) return new Response('Unauthorized', { status: 401 })
  let payload
  try { payload = JSON.parse(new URLSearchParams(body).get('payload') || '') } catch (_) {
    return new Response('Bad Request', { status: 400 })
  }
  if (!payload || payload.type !== 'block_actions') return new Response('', { status: 200 })
  const action      = (payload.actions || [])[0] || {}
  const userId      = (payload.user && payload.user.id) || ''
  const responseUrl = payload.response_url || ''
  const [actionId, nonce] = String(action.value || '').split('|')
  if (!['hermes_approve', 'hermes_deny'].includes(action.action_id) ||
      !HERMES_ACTION_ID_RE.test(actionId || '') || !HERMES_NONCE_RE.test(nonce || '')) {
    return new Response('', { status: 200 })
  }
  event.waitUntil((async () => {
    const kv = approvalsKv()
    if (!kv) return postResponseUrl(responseUrl, '⚠️ Hermes approvals are not configured on the relay')
    if (!approverAllowed(userId)) return postResponseUrl(responseUrl, '⛔ You are not authorized to approve Hermes repairs')
    if (!await kv.get(`reauth:${userId}`)) {
      return postResponseUrl(responseUrl, '🔐 Re-authenticate first: run `/hermes-auth` (valid for 24h)')
    }
    if (action.action_id === 'hermes_approve') {
      await kv.put(`approval:${actionId}`,
        JSON.stringify({ approved_by: userId, approved_at: Date.now(), nonce }),
        { expirationTtl: APPROVAL_TTL_SECONDS })
      return replaceResponseUrl(responseUrl, `✅ ${actionId} approved by <@${userId}> — applying on the next Hermes poll (up to ~5 min)`)
    }
    return replaceResponseUrl(responseUrl, `🚫 ${actionId} denied by <@${userId}> — dismissed; Hermes may propose it again`)
  })())
  return new Response('', { status: 200 })
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
    const data = await resp.json().catch(() => ({}))
    if (resp.status === 409) return { ok: false, conflict: data.error || 'cluster job already running' }
    if (resp.status === 403) return { ok: false, conflict: data.error || 'forbidden' }
    if (resp.status === 400) return { ok: false, conflict: data.error || 'bad request' }
    return { ok: resp.ok, conflict: null, data }
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

async function replaceResponseUrl(url, text) {
  if (!url) return
  await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, replace_original: true }),
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
  const pathname = new URL(req.url).pathname
  if (pathname === '/hermes/approvals' || pathname.startsWith('/hermes/approvals/')) {
    return handleDrain(req, pathname)
  }
  if (req.method !== 'POST') return new Response('Not Found', { status: 404 })

  if (pathname === '/slack/interactivity') return handleInteractivity(req, event)

  if (pathname === '/slack/events') {
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
  const channelId   = p.get('channel_id')  || ''
  const userId      = p.get('user_id')    || ''
  const userName    = p.get('user_name')  || ''
  const role        = COMMAND_ROLES[command] || 'reader'
  const actor       = userName ? `slack:${userName}${userId ? `:${userId}` : ''}` : `slack:${userId || 'unknown'}`
  const meta        = { role, actor, sourceCommand: command }

  if (!ALLOWED_COMMANDS.has(command)) return jsonReply(`Unknown command: ${command}`, threadTs)

  if (command === '/hermes-auth') {
    const kv = approvalsKv()
    if (!kv) return jsonReply('⚠️ Hermes approvals are not configured on the relay', threadTs, true)
    if (!approverAllowed(userId)) return jsonReply('⛔ You are not authorized to approve Hermes repairs', threadTs, true)
    await kv.put(`reauth:${userId}`, '1', { expirationTtl: REAUTH_TTL_SECONDS })
    return jsonReply('🔐 Re-authenticated for 24h — you can now approve Hermes repairs.', threadTs, true)
  }

  if (command === '/cluster-up') {
    const { provider, error } = resolveProviderStrict(text)
    if (error) return jsonReply(`⚠️ ${error}\nUsage: ${command} <cluster>\nClusters: aws, gcp, az, hostinger\nExample: ${command} aws\n${CLUSTER_ARG_USAGE}`, threadTs, true)
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
    const { provider, error } = resolveProviderStrict(text)
    if (error) return jsonReply(`⚠️ ${error}\nUsage: ${command} <cluster>\nClusters: aws, gcp, az, hostinger\nExample: ${command} aws\n${CLUSTER_ARG_USAGE}`, threadTs, true)
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
    const payload = { provider, response_url: responseUrl, channel_id: channelId }
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
    const payload = { ...parsed.payload, response_url: responseUrl, channel_id: channelId }
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
      return jsonReply(CLUSTER_RESUME_USAGE, threadTs)
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
    if (cleanupText && !['preview', 'confirm', 'apply'].includes(cleanupText)) {
      return jsonReply(CLEANUP_USAGE, threadTs)
    }
    const confirm = ['confirm', 'apply'].includes(cleanupText)
    event.waitUntil((async () => {
      const payload = { confirm, response_url: responseUrl, channel_id: p.get('channel_id') || '' }
      if (threadTs) payload.thread_ts = threadTs
      const { ok, conflict } = await relay('/api/v1/cleanup-stale-sandbox', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`🧹 ${confirm ? 'Applying' : 'Previewing'} stale ACG sandbox cleanup…`, threadTs, true)
  }

  if (command === '/k3dm') {
    const parsed = parseK3dm(text)
    if (parsed.error) return jsonReply(parsed.error, threadTs, true)
    const payload = { ...parsed.payload, slack_user_id: userId, response_url: responseUrl }
    const isHelp = payload.target === 'help'
    event.waitUntil((async () => {
      const { ok, conflict, data } = await relay('/api/v1/make', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
      else if (isHelp && data && data.text) await postResponseUrl(responseUrl, data.text)
    })())
    return jsonReply(isHelp ? '📋 Fetching /k3dm targets…' : `🛠️ Queuing \`make ${payload.target}\`…`, threadTs, true)
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
    if (!question) return jsonReply(`Usage: ${command} <question>\nExample: ${command} investigate the latest failed check`, threadTs)
    const payload = { agent, question, response_url: responseUrl, channel_id: channelId }
    if (threadTs) payload.thread_ts = threadTs
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/ask', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`🤖 Asking ${agent}…`, threadTs, true)
  }

  if (command === '/ask-docs') {
    if (!text || text === '--sources' || text === '-s') return jsonReply(ASK_DOCS_USAGE, threadTs)
    const payload = { question: text, response_url: responseUrl, channel_id: channelId }
    if (threadTs) payload.thread_ts = threadTs
    event.waitUntil((async () => {
      const { ok, conflict } = await relay('/api/v1/ask-docs', payload, meta)
      if (conflict) await postResponseUrl(responseUrl, `⚠️ ${conflict}`)
      else if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply('📚 Searching the docs…', threadTs, true)
  }

  if (command === '/argocd-upgrade') {
    const parts   = text.split(/\s+/)
    const version = parts[0] || ''
    const stage   = parts[1] || 'infra'
    if (!version) return jsonReply(ARGOCD_UPGRADE_USAGE, threadTs)
    if (!['acg', 'infra'].includes(stage)) return jsonReply(`${ARGOCD_UPGRADE_USAGE}\nStage must be acg or infra.`, threadTs)
    event.waitUntil((async () => {
      const { ok } = await relay('/api/v1/argocd-upgrade',
        { chart_version: version, stage, response_url: responseUrl }, meta)
      if (!ok) await postResponseUrl(responseUrl, '❌ Webhook unreachable — try again in a moment')
    })())
    return jsonReply(`⏳ Upgrading ArgoCD to chart ${version} on ${stage}…`, threadTs, true)
  }

  return jsonReply('Unhandled command', threadTs)
}
