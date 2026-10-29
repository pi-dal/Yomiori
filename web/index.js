// Kotoba AI relay: the app sends messages, this Worker calls AirRouter.
//   POST /api/ai/chat {messages:[{role,content}], stream?:bool, json?:bool}
//     stream=true  -> text/event-stream (OpenAI chunks)
//     otherwise    -> {text}
// Access: per-install daily cap (x-install-id header). No accounts.
import {
  allowance, callRouter, costOf, ensureMeterSchema, record,
  RouterCallError, relayStream, routerError,
} from "./airrouter.js";

const CHAT_MODEL = "@preset/airrouter-free";
const DAILY_USD = 0.15;
const PENDING_ESTIMATE_USD = 0.01;
const MAX_MESSAGES = 40;
const MAX_CHARS = 12_000;

const fail = (status, code) => Response.json({ error: true, code }, { status });

function failure(response) {
  const kind = response instanceof RouterCallError ? response.kind : routerError(response);
  if (kind === "unpaid" || kind === "disabled" || kind === "unavailable") return fail(503, "ai_unavailable");
  if (kind === "busy") return fail(429, "busy");
  return fail(502, "ai_failed");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/api/ai/chat") return new Response("not found", { status: 404 });
    if (request.method !== "POST") return new Response("method not allowed", { status: 405 });
    const install = (request.headers.get("x-install-id") ?? "").toLowerCase();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(install)) return fail(401, "install_required");
    const subject = `install:${install}`;
    await ensureMeterSchema(env.DB);
    const left = await allowance(env.DB, subject, { dailyUSD: DAILY_USD, pendingEstimateUSD: PENDING_ESTIMATE_USD });
    if (!left.allowed) return fail(429, "daily_limit_reached");

    const body = await request.json().catch(() => null);
    const messages = Array.isArray(body?.messages) ? body.messages : null;
    if (!messages || messages.length === 0 || messages.length > MAX_MESSAGES ||
        messages.some((m) => !["system", "user", "assistant"].includes(m?.role) ||
          typeof m.content !== "string" || m.content.length > MAX_CHARS)) {
      return fail(400, "invalid_request");
    }
    const stream = body.stream === true;
    const upstream = await callRouter(
      "openrouter/api/v1/chat/completions",
      { model: CHAT_MODEL, messages: messages.map(({ role, content }) => ({ role, content })), stream, max_tokens: 2000 },
      { user: subject, signal: request.signal },
    );
    if (!upstream.ok) return failure(upstream);
    const { requestId, costUSD } = costOf(upstream);
    await record(env.DB, subject, requestId, costUSD);
    if (stream) return relayStream(upstream);
    const result = await upstream.json();
    return Response.json({ text: result.choices?.[0]?.message?.content ?? "" });
  },
};
