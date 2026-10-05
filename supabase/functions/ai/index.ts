// EventLens AI server (Supabase Edge Function). Holds the owner's Anthropic
// key so nobody using the app needs their own, checks each request comes
// from a signed-in account, and applies a daily allowance that reward
// videos can top up. It stores usage counts only, never what people wrote
// or photographed. Setup: docs/AI_SERVER.md.
//
//   POST /ai/messages      { task, betas, body } -> Claude Messages response
//   GET  /ai/allowance     today's allowance, without using any
//   GET  /ai/admob-reward  AdMob server-side verification callback

import Anthropic from "npm:@anthropic-ai/sdk@^0.131.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5";

import {
  BadRequest,
  base64UrlToBytes,
  configFrom,
  dayKey,
  derToRawSignature,
  FALLBACK_BETA,
  isTask,
  shapeRequest,
  splitAdMobQuery,
  TASKS,
} from "./logic.ts";

const config = configFrom((name) => Deno.env.get(name));
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

// ---- Accounts ------------------------------------------------------------

// The app signs people in with Firebase today; its ID tokens are checked
// against Google's published keys. Moving sign-in to Supabase is a later,
// separate step (docs/AI_SERVER.md, "Scheduled").
const firebaseProject = Deno.env.get("FIREBASE_PROJECT_ID")!;
const firebaseKeys = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

async function accountFrom(req: Request): Promise<string | null> {
  const header = req.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, firebaseKeys, {
      issuer: `https://securetoken.google.com/${firebaseProject}`,
      audience: firebaseProject,
    });
    return typeof payload.sub === "string" && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}

// ---- Allowance -----------------------------------------------------------

async function remaining(uid: string, day: string): Promise<number> {
  const { data, error } = await db.rpc("ai_allowance", {
    p_uid: uid,
    p_day: day,
    p_daily: config.dailyCredits,
  });
  if (error) throw error;
  return data as number;
}

async function consume(
  uid: string,
  day: string,
  cost: number,
): Promise<{ ok: boolean; remaining: number }> {
  const { data, error } = await db.rpc("ai_consume", {
    p_uid: uid,
    p_day: day,
    p_cost: cost,
    p_daily: config.dailyCredits,
  });
  if (error) throw error;
  const row = (data as { ok: boolean; remaining: number }[])[0];
  return row;
}

async function refund(uid: string, day: string, cost: number) {
  await db.rpc("ai_refund", { p_uid: uid, p_day: day, p_cost: cost });
}

// ---- Responses -----------------------------------------------------------

function json(
  status: number,
  body: unknown,
  allowance?: number,
): Response {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (allowance !== undefined) {
    headers["x-ai-remaining"] = String(Math.max(allowance, 0));
    headers["x-ai-daily"] = String(config.dailyCredits);
  }
  return new Response(JSON.stringify(body), { status, headers });
}

const fail = (status: number, message: string, allowance?: number) =>
  json(status, { error: { message } }, allowance);

// ---- Routes --------------------------------------------------------------

const MAX_REQUEST_BYTES = 20 * 1024 * 1024;

async function messages(req: Request): Promise<Response> {
  const uid = await accountFrom(req);
  if (!uid) return fail(401, "Sign in again.");

  // Ten resized photos fit comfortably; anything far bigger isn't the app.
  const size = Number(req.headers.get("content-length") ?? 0);
  if (size > MAX_REQUEST_BYTES) return fail(413, "The request is too large.");

  let payload: { task?: unknown; betas?: unknown; body?: unknown };
  try {
    payload = await req.json();
  } catch {
    return fail(400, "The request is not JSON.");
  }
  if (!isTask(payload.task)) return fail(400, "Unknown task.");
  const task = payload.task;

  let shaped: Record<string, unknown>;
  try {
    shaped = shapeRequest(task, payload.body, config);
  } catch (e) {
    if (e instanceof BadRequest) return fail(400, e.message);
    throw e;
  }

  const day = dayKey(new Date());
  const cost = TASKS[task].cost;
  const spent = await consume(uid, day, cost);
  if (!spent.ok) {
    return fail(402, "Today's AI allowance is used up.", spent.remaining);
  }

  try {
    // Streaming keeps long, high-effort requests from hitting HTTP timeouts;
    // the app still receives one complete Messages response.
    const message = await anthropic.beta.messages
      .stream({
        ...shaped,
        betas: [FALLBACK_BETA],
      } as unknown as Anthropic.Beta.Messages.MessageCreateParamsStreaming)
      .finalMessage();
    return json(200, message, spent.remaining);
  } catch (e) {
    await refund(uid, day, cost);
    const left = spent.remaining + cost;
    if (e instanceof Anthropic.RateLimitError) {
      return fail(429, "The AI is busy.", left);
    }
    if (e instanceof Anthropic.BadRequestError) {
      return fail(400, e.message, left);
    }
    if (
      e instanceof Anthropic.AuthenticationError ||
      e instanceof Anthropic.PermissionDeniedError
    ) {
      console.error("Anthropic key rejected; check ANTHROPIC_API_KEY.");
      return fail(500, "The AI server is not set up correctly.", left);
    }
    if (e instanceof Anthropic.APIError) {
      return fail(503, "The AI is temporarily unavailable.", left);
    }
    if (e instanceof Anthropic.APIConnectionError) {
      return fail(503, "The AI could not be reached.", left);
    }
    throw e;
  }
}

async function allowance(req: Request): Promise<Response> {
  const uid = await accountFrom(req);
  if (!uid) return fail(401, "Sign in again.");
  const left = await remaining(uid, dayKey(new Date()));
  return json(200, { remaining: left, daily: config.dailyCredits }, left);
}

// AdMob calls this after a reward video finishes. The app sets the
// account's id as the ad's user id (ServerSideVerificationOptions), and the
// callback is signed with Google's keys, so it can't be faked from a phone.
const ADMOB_KEYS_URL =
  "https://www.gstatic.com/admob/reward/verifier-keys.json";

async function admobKey(keyId: string): Promise<CryptoKey | null> {
  const res = await fetch(ADMOB_KEYS_URL);
  if (!res.ok) return null;
  const { keys } = await res.json() as {
    keys: { keyId: number; base64: string }[];
  };
  const key = keys.find((k) => String(k.keyId) === keyId);
  if (!key) return null;
  return crypto.subtle.importKey(
    "spki",
    base64UrlToBytes(key.base64),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
}

async function admobReward(req: Request): Promise<Response> {
  if (!config.adsEnabled) return fail(404, "Reward videos are not on yet.");
  const url = new URL(req.url);
  const signed = splitAdMobQuery(url.search);
  if (!signed) return fail(400, "Unsigned callback.");
  const key = await admobKey(signed.keyId);
  if (!key) return fail(400, "Unknown signing key.");
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    derToRawSignature(base64UrlToBytes(signed.signature)),
    new TextEncoder().encode(signed.message),
  );
  if (!valid) return fail(400, "Bad signature.");

  const uid = url.searchParams.get("user_id");
  const transaction = url.searchParams.get("transaction_id");
  if (!uid || !transaction) return fail(400, "Missing user or transaction.");
  const { error } = await db.rpc("ai_add_bonus", {
    p_tx: transaction,
    p_uid: uid,
    p_day: dayKey(new Date()),
    p_credits: config.adCredits,
  });
  if (error) throw error;
  // AdMob only needs a 200; repeats of the same transaction add nothing.
  return new Response("ok");
}

Deno.serve(async (req) => {
  const path = new URL(req.url).pathname.replace(/\/+$/, "");
  try {
    if (req.method === "POST" && path.endsWith("/messages")) {
      return await messages(req);
    }
    if (req.method === "GET" && path.endsWith("/allowance")) {
      return await allowance(req);
    }
    if (req.method === "GET" && path.endsWith("/admob-reward")) {
      return await admobReward(req);
    }
    return fail(404, "Not found.");
  } catch (e) {
    console.error("AI server error:", e instanceof Error ? e.message : e);
    return fail(500, "The AI server had a problem.");
  }
});
