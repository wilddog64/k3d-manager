import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';

// Slice F checkout load generator. Drives POST /api/orders (order-service) with
// deterministic synthetic items — the order records productId/productName/unitPrice
// from the request body, so no real seeded product IDs are needed. Payment is
// downstream (order -> payment-service via queue, Stripe test mode).
//
// Config via env (all injected by loadtest.sh per stage):
//   LOADTEST_TARGET_URL   base URL to order-service (laptop port-forward, e.g. http://localhost:18081)
//   LOADTEST_TOKEN        bearer access token (minted once per stage by the shell helper)
//   LOADTEST_RUN_ID       immutable run id
//   LOADTEST_STAGE        stage label (target concurrency)
//   LOADTEST_VUS          virtual users for this stage
//   LOADTEST_DURATION     stage duration (e.g. 60s)
//   LOADTEST_POLL_ORDER   "1" to poll GET /api/orders/{id} for order/payment state (default off)
//   LOADTEST_SLEEP        per-iteration think time seconds (default 1)

const TARGET = __ENV.LOADTEST_TARGET_URL || 'http://localhost:18081';
const TOKEN = __ENV.LOADTEST_TOKEN || '';
const RUN_ID = __ENV.LOADTEST_RUN_ID || 'loadtest-dev';
const STAGE = __ENV.LOADTEST_STAGE || '0';
const VUS = parseInt(__ENV.LOADTEST_VUS || '10', 10);
const DURATION = __ENV.LOADTEST_DURATION || '60s';
const POLL_ORDER = __ENV.LOADTEST_POLL_ORDER === '1';
const THINK = parseFloat(__ENV.LOADTEST_SLEEP || '1');

// Bounded-label custom metrics (plan §2). k6's remote-write output prefixes these
// with `k6_` (so the dashboard queries `k6_checkout_load_*`).
const latency = new Trend('checkout_load_latency_seconds');
const requests = new Counter('checkout_load_requests_total');
const orders = new Counter('checkout_load_orders_total');
const payments = new Counter('checkout_load_payments_total');
const idempotencyFailures = new Counter('checkout_load_idempotency_failures_total');
const errorRate = new Rate('checkout_load_error_rate');

export const options = {
  scenarios: {
    checkout: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
      tags: { stage: STAGE, run_id: RUN_ID },
    },
  },
  // Abort the stage early if the client-observed error rate blows past the gate;
  // the shell controller owns the authoritative stop decision from Prometheus.
  thresholds: {
    checkout_load_error_rate: [{ threshold: 'rate<0.10', abortOnFail: false }],
  },
};

function synthOrder(vu, iter) {
  const customerId = `${RUN_ID}-vu${vu}-it${iter}`;
  const qty = 1 + (iter % 3);
  return {
    customerId: customerId,
    items: [
      {
        productId: `synthetic-${(iter % 20) + 1}`,
        productName: `Synthetic Product ${(iter % 20) + 1}`,
        quantity: qty,
        unitPrice: 19.99,
      },
    ],
    shippingAddress: {
      street: '1 Load Test Way',
      city: 'Bellevue',
      state: 'WA',
      postalCode: '98004',
      country: 'US',
    },
    currency: 'USD',
  };
}

export default function () {
  const body = synthOrder(__VU, __ITER);
  const idempotencyKey = `${RUN_ID}-${__VU}-${__ITER}`;
  const tags = { stage: STAGE, run_id: RUN_ID };

  const res = http.post(`${TARGET}/api/orders`, JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${TOKEN}`,
      'X-Idempotency-Key': idempotencyKey,
      'X-Correlation-ID': idempotencyKey,
    },
    tags: tags,
  });

  latency.add(res.timings.duration / 1000.0, tags);
  requests.add(1, Object.assign({ result: res.status >= 200 && res.status < 400 ? 'ok' : 'error' }, tags));
  const created = check(res, {
    'order created (201)': (r) => r.status === 201,
  });
  errorRate.add(!created, tags);

  if (res.status === 409) {
    idempotencyFailures.add(1, tags);
  }

  let orderId = null;
  if (created) {
    orders.add(1, Object.assign({ state: 'created' }, tags));
    try {
      orderId = res.json('id') || res.json('orderId');
    } catch (e) {
      orderId = null;
    }
  } else {
    orders.add(1, Object.assign({ state: 'failed' }, tags));
  }

  if (POLL_ORDER && orderId) {
    const poll = http.get(`${TARGET}/api/orders/${orderId}`, {
      headers: { Authorization: `Bearer ${TOKEN}` },
      tags: tags,
    });
    if (poll.status === 200) {
      let paymentState = 'unknown';
      try {
        paymentState = poll.json('paymentStatus') || poll.json('status') || 'unknown';
      } catch (e) {
        paymentState = 'unknown';
      }
      payments.add(1, Object.assign({ state: String(paymentState), gateway: 'stripe' }, tags));
    }
  }

  sleep(THINK);
}
