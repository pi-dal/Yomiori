// airrouter.js — calling AirRouter from an AirHost Worker, plus a small
// per-subject spending meter in the Worker's own D1 database. Copy this file
// next to the Worker's index.js (web/airrouter.js) and import it:
//
//   import { callRouter, relayStream, routerError, allowance, record } from "./airrouter.js";
//
// AirHost runs no build step and ships no node_modules: this file is plain,
// dependency-free ESM and must stay that way.
//
// AirRouter bills the owner's AirRouter Balance for every call. It does not
// know the app's users and does not limit them; `x-router-user` is only a
// label for the owner's usage view. Any per-user or per-device limit is the
// Worker's job — that is what the meter below is for.

/** Where Workers reach AirRouter. Calls from a deployed Worker need no key. */
export const ROUTER_BASE = "https://apps.air.build/router";

/**
 * POST a JSON body to an AirRouter route, e.g.
 * `callRouter("openrouter/api/v1/chat/completions", {...}, { user: "user:42" })`.
 * Returns the raw Response: check `routerError(response)` before using it.
 */
export function callRouter(path, body, options = {}) {
  const { user, signal, method = "POST", base = ROUTER_BASE, fetch: fetcher = fetch } = options;
  const headers = { "content-type": "application/json" };
  if (user) headers["x-router-user"] = String(user).slice(0, 128);
  return fetcher(`${base}/${path.replace(/^\/+/, "")}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    ...(signal ? { signal } : {}),
  });
}

/**
 * Pass an upstream SSE stream straight through to the app, keeping only the
 * headers the app (or the Worker's meter) needs. The stream is not buffered:
 * tokens reach the app as the model produces them.
 */
export function relayStream(upstream) {
  const headers = new Headers({
    "content-type": upstream.headers.get("content-type") ?? "text/event-stream",
    "cache-control": "no-cache",
  });
  for (const name of ["x-router-request-id", "x-router-cost-status", "x-router-cost"]) {
    const value = upstream.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  return new Response(upstream.body, { status: upstream.status, headers });
}

/**
 * What a router response cost. `status` is "final" (cost known now) or
 * "pending" (a stream or a task that settles later: look it up with
 * `lookupCost(requestId)` after it ended). `costUSD` is null while pending.
 */
export function costOf(response) {
  const requestId = response.headers.get("x-router-request-id");
  const status = response.headers.get("x-router-cost-status");
  const cost = response.headers.get("x-router-cost");
  return {
    requestId,
    status: status === "final" || status === "pending" ? status : null,
    costUSD: status === "final" && cost !== null ? Number(cost) : null,
  };
}

/** The settled cost of an earlier call in dollars, or null while it is still running. */
export async function lookupCost(requestId, options = {}) {
  const { base = ROUTER_BASE, fetch: fetcher = fetch } = options;
  const response = await fetcher(`${base}/_router/requests/${encodeURIComponent(requestId)}`);
  if (!response.ok) return null;
  const row = await response.json();
  if (row.status === "running") return null;
  // Failed, cancelled and unpriced calls cost nothing.
  return row.costUSD === null || row.costUSD === undefined ? 0 : Number(row.costUSD);
}

/**
 * AirRouter's own refusals (responses with `x-router-error`), in a few kinds
 * the app can act on. Null means the router did not refuse: either success
 * or the provider's own error, relayed as is.
 *
 *   "unpaid"      402: AirRouter Balance empty, no payer, or today's limit reached;
 *                 429: the free model's daily allowance is used up
 *   "disabled"    403: AirRouter is turned off for this app
 *   "busy"        429: too many calls in flight; retry later
 *   "unavailable" 502/503: the provider is down
 *   "unsupported" 404: route or model endpoint not relayed
 *   "other"       anything else the router refused
 */
export function routerError(response) {
  const code = response.headers.get("x-router-error");
  if (code === null) return null;
  switch (code) {
    case "payment_required":
    case "billing_account_required":
    case "billing_account_closed":
    case "spend_limit_reached":
    case "free_allowance_reached":
      return "unpaid";
    case "router_disabled":
      return "disabled";
    case "billing_concurrency_limit":
      return "busy";
    case "provider_unavailable":
      return "unavailable";
    case "route_not_supported":
      return "unsupported";
    default:
      return "other";
  }
}

/**
 * Run a fal queue task: submit, poll its status URL, fetch the result.
 * Returns `{ result, requestId, costUSD }`. Each poll is a subrequest and a
 * Worker request has a limited number of them, so keep `pollMs` at a few
 * seconds; long jobs (video) belong in a client-side poll instead.
 */
export async function falTask(endpoint, input, options = {}) {
  const {
    user,
    base = ROUTER_BASE,
    fetch: fetcher = fetch,
    timeoutMs = 120_000,
    pollMs = 3_000,
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    now = () => Date.now(),
  } = options;
  const submitted = await callRouter(`fal/${endpoint}`, input, { user, base, fetch: fetcher });
  if (!submitted.ok) throw new RouterCallError(submitted);
  const job = await submitted.json();
  const requestId = submitted.headers.get("x-router-request-id");
  const deadline = now() + timeoutMs;
  for (;;) {
    const status = await fetcher(job.status_url);
    if (!status.ok) throw new RouterCallError(status);
    const state = (await status.json()).status;
    if (state === "COMPLETED") break;
    if (state !== "IN_QUEUE" && state !== "IN_PROGRESS") {
      throw new Error(`fal task ended as ${state}`);
    }
    if (now() + pollMs > deadline) throw new Error("fal task timed out");
    await sleep(pollMs);
  }
  const result = await fetcher(job.response_url);
  if (!result.ok) throw new RouterCallError(result);
  const { costUSD } = costOf(result);
  return { result: await result.json(), requestId, costUSD };
}

/** A failed router call, carrying its status and `routerError` kind. */
export class RouterCallError extends Error {
  constructor(response) {
    super(`router call failed with ${response.status}`);
    this.status = response.status;
    this.kind = routerError(response);
  }
}

// ---------------------------------------------------------------------------
// Spending meter (D1). A "subject" is whoever the app limits: a signed-in
// user (`user:<id>`) or an anonymous install on a trial (`install:<id>`).
// Costs are stored in micro-dollars. A call whose cost is still pending
// (streams) counts as `pendingEstimateUSD` until it settles; settling happens
// lazily, the next time the subject asks for an allowance.
// ---------------------------------------------------------------------------

const MICRO = 1_000_000;

export async function ensureMeterSchema(db) {
  await db.exec(
    "CREATE TABLE IF NOT EXISTS ai_usage (request_id TEXT PRIMARY KEY, subject TEXT NOT NULL, " +
      "day TEXT NOT NULL, cost_micro INTEGER, created_at INTEGER NOT NULL)",
  );
  await db.exec("CREATE INDEX IF NOT EXISTS ai_usage_subject_day ON ai_usage (subject, day)");
}

const today = (at = Date.now()) => new Date(at).toISOString().slice(0, 10);

/** Record one call for a subject. `costUSD` null = pending (settled later). */
export async function record(db, subject, requestId, costUSD) {
  if (!requestId) return;
  await db
    .prepare(
      "INSERT OR IGNORE INTO ai_usage (request_id, subject, day, cost_micro, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(requestId, subject, today(), costUSD === null ? null : Math.round(costUSD * MICRO), Date.now())
    .run();
}

/** Look up the final cost of a subject's pending calls (a few at a time). */
export async function settle(db, subject, options = {}) {
  const { limit = 5 } = options;
  const { results } = await db
    .prepare("SELECT request_id FROM ai_usage WHERE subject = ? AND cost_micro IS NULL ORDER BY created_at LIMIT ?")
    .bind(subject, limit)
    .all();
  for (const row of results) {
    const cost = await lookupCost(row.request_id, options);
    if (cost === null) continue;
    await db
      .prepare("UPDATE ai_usage SET cost_micro = ? WHERE request_id = ?")
      .bind(Math.round(cost * MICRO), row.request_id)
      .run();
  }
}

/**
 * Whether a subject may make another call under `plan`:
 * `{ dailyUSD?, totalUSD?, pendingEstimateUSD = 0.01 }`. Returns
 * `{ allowed, reason, spentTodayUSD, spentTotalUSD }`; `reason` is
 * "daily_limit_reached" or "total_limit_reached" when not allowed.
 */
export async function allowance(db, subject, plan, options = {}) {
  await settle(db, subject, options);
  const estimate = Math.round((plan.pendingEstimateUSD ?? 0.01) * MICRO);
  const sum = async (where, ...values) => {
    const row = await db
      .prepare(
        `SELECT COALESCE(SUM(COALESCE(cost_micro, ${estimate})), 0) AS spent FROM ai_usage WHERE subject = ?${where}`,
      )
      .bind(subject, ...values)
      .first();
    return Number(row?.spent ?? 0) / MICRO;
  };
  const spentTodayUSD = await sum(" AND day = ?", today());
  const spentTotalUSD = plan.totalUSD === undefined ? spentTodayUSD : await sum("");
  let reason = null;
  if (plan.totalUSD !== undefined && spentTotalUSD >= plan.totalUSD) reason = "total_limit_reached";
  else if (plan.dailyUSD !== undefined && spentTodayUSD >= plan.dailyUSD) reason = "daily_limit_reached";
  return { allowed: reason === null, reason, spentTodayUSD, spentTotalUSD };
}
