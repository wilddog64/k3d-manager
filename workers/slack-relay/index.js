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

async function relay(endpoint, payload, event) {
  event.waitUntil(
    fetch(`${WEBHOOK_URL}${endpoint}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${WEBHOOK_TOKEN}`,
        'Content-Type':  'application/json'
      },
      body: JSON.stringify(payload)
    })
  )
}

function jsonReply(text) {
  return new Response(JSON.stringify({ text, response_type: 'in_channel' }),
    { status: 200, headers: { 'Content-Type': 'application/json' } })
}

addEventListener('fetch', event => {
  event.respondWith(handle(event))
})

async function handle(event) {
  const req = event.request
  if (req.method !== 'POST') return new Response('Not Found', { status: 404 })

  const body = await req.text()
  if (!await verifySlack(req, body)) return new Response('Unauthorized', { status: 401 })

  const p           = new URLSearchParams(body)
  const command     = p.get('command')    || ''
  const text        = (p.get('text')      || '').trim()
  const responseUrl = p.get('response_url') || ''

  if (!ALLOWED_COMMANDS.has(command)) return jsonReply(`Unknown command: ${command}`)

  if (command === '/acg-up') {
    const provider = VALID_PROVIDERS.has(text) ? text : 'aws'
    await relay('/api/v1/cluster', { action: 'up', provider, response_url: responseUrl }, event)
    return jsonReply(`⏳ Bringing up ACG cluster (${provider})…`)
  }

  if (command === '/acg-down') {
    await relay('/api/v1/cluster', { action: 'down', response_url: responseUrl }, event)
    return jsonReply('⏳ Tearing down ACG cluster…')
  }

  if (command === '/acg-status') {
    await relay('/api/v1/cluster-status', { response_url: responseUrl }, event)
    return jsonReply('🔍 Checking ACG cluster status…')
  }

  if (command === '/argocd-upgrade') {
    const parts   = text.split(/\s+/)
    const version = parts[0] || ''
    const stage   = parts[1] || 'infra'
    if (!version) return jsonReply('Usage: /argocd-upgrade <chart_version> [acg|infra]')
    if (!['acg', 'infra'].includes(stage)) return jsonReply('stage must be acg or infra')
    await relay('/api/v1/argocd-upgrade',
      { chart_version: version, stage, response_url: responseUrl }, event)
    return jsonReply(`⏳ Upgrading ArgoCD to chart ${version} on ${stage}…`)
  }

  return jsonReply('Unhandled command')
}
