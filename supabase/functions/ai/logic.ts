// Pure rules for the EventLens AI server: what each task costs, which
// model it runs on, and how a request from the app is reshaped before it
// reaches Anthropic. No I/O here, so it can be tested on its own.

export type Task = "describe" | "graph" | "label" | "advise";

export interface TaskRule {
  /** Allowance credits one request uses. */
  cost: number;
  /** Highest max_tokens the server allows for the task. */
  maxTokens: number;
}

/** Costs follow what each request actually spends: a photo description or
 * a graph pass is several times the price of a label. */
export const TASKS: Record<Task, TaskRule> = {
  describe: { cost: 4, maxTokens: 32000 },
  graph: { cost: 3, maxTokens: 32000 },
  label: { cost: 1, maxTokens: 4096 },
  advise: { cost: 1, maxTokens: 4000 },
};

export const FALLBACK_BETA = "server-side-fallback-2026-07-01";

const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
export type Effort = (typeof EFFORTS)[number];

export interface Config {
  /** Model per task (the server decides, never the phone). */
  models: Record<Task, string>;
  /** The highest effort any request may use. */
  maxEffort: Effort;
  /** Free credits per account per day. */
  dailyCredits: number;
  /** Credits one confirmed reward video adds. */
  adCredits: number;
  /** Whether reward-video top-ups are accepted yet. */
  adsEnabled: boolean;
}

export const DEFAULT_MODEL = "claude-opus-5-5";

/** Reads the server settings from environment variables (see
 * docs/AI_SERVER.md); anything unset uses the defaults. */
export function configFrom(env: (name: string) => string | undefined): Config {
  const model = env("AI_MODEL") || DEFAULT_MODEL;
  const models = {} as Record<Task, string>;
  for (const task of Object.keys(TASKS) as Task[]) {
    models[task] = env(`AI_MODEL_${task.toUpperCase()}`) || model;
  }
  const maxEffort = env("AI_MAX_EFFORT") as Effort | undefined;
  return {
    models,
    maxEffort: maxEffort && EFFORTS.includes(maxEffort) ? maxEffort : "high",
    dailyCredits: positiveInt(env("AI_DAILY_CREDITS"), 20),
    adCredits: positiveInt(env("AI_AD_CREDITS"), 4),
    adsEnabled: env("ADS_ENABLED") === "true",
  };
}

function positiveInt(value: string | undefined, fallback: number): number {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : fallback;
}

export function isTask(value: unknown): value is Task {
  return typeof value === "string" && value in TASKS;
}

export class BadRequest extends Error {}

/**
 * Rebuilds the app's Messages request from the fields the app is allowed to
 * set. The server picks the model, caps effort and output length, and turns
 * on refusal fallbacks; anything else the request carries is dropped.
 */
export function shapeRequest(
  task: Task,
  body: unknown,
  config: Config,
): Record<string, unknown> {
  if (!body || typeof body !== "object") throw new BadRequest("No request.");
  const b = body as Record<string, unknown>;
  if (!Array.isArray(b.messages) || b.messages.length === 0) {
    throw new BadRequest("The request has no messages.");
  }

  const requested = Number(b.max_tokens);
  const maxTokens = Number.isFinite(requested) && requested > 0
    ? Math.min(Math.floor(requested), TASKS[task].maxTokens)
    : TASKS[task].maxTokens;

  const out = (b.output_config ?? {}) as Record<string, unknown>;
  const outputConfig: Record<string, unknown> = {
    effort: capEffort(out.effort, config.maxEffort),
  };
  if (out.format !== undefined) outputConfig.format = out.format;

  const shaped: Record<string, unknown> = {
    model: config.models[task],
    max_tokens: maxTokens,
    thinking: { type: "adaptive" },
    output_config: outputConfig,
    fallbacks: "default",
    messages: b.messages,
  };
  if (b.system !== undefined) shaped.system = b.system;
  return shaped;
}

export function capEffort(requested: unknown, max: Effort): Effort {
  const r = EFFORTS.indexOf(requested as Effort);
  const m = EFFORTS.indexOf(max);
  if (r < 0) return max === "low" ? "low" : "medium";
  return EFFORTS[Math.min(r, m)];
}

/** The allowance day, in UTC, as YYYY-MM-DD. */
export function dayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

// ---- Reward-video confirmations (AdMob server-side verification) ---------

/** The signed part of an AdMob callback and its signature. AdMob signs the
 * query string up to (not including) "&signature=". */
export function splitAdMobQuery(
  query: string,
): { message: string; signature: string; keyId: string } | null {
  const q = query.startsWith("?") ? query.slice(1) : query;
  const at = q.indexOf("&signature=");
  if (at < 0) return null;
  const message = q.slice(0, at);
  const rest = new URLSearchParams(q.slice(at + 1));
  const signature = rest.get("signature");
  const keyId = rest.get("key_id");
  if (!signature || !keyId) return null;
  return { message, signature, keyId };
}

export function base64UrlToBytes(value: string): Uint8Array<ArrayBuffer> {
  const b64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/** Converts a DER ECDSA signature (what AdMob sends) to the 64-byte r||s
 * form Web Crypto verifies. */
export function derToRawSignature(der: Uint8Array): Uint8Array<ArrayBuffer> {
  let i = 0;
  if (der[i++] !== 0x30) throw new Error("Not a DER sequence.");
  i += der[i] & 0x80 ? (der[i] & 0x7f) + 1 : 1;
  const part = (): Uint8Array => {
    if (der[i++] !== 0x02) throw new Error("Not a DER integer.");
    const len = der[i++];
    let bytes = der.slice(i, i + len);
    i += len;
    while (bytes.length > 32 && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > 32) throw new Error("Integer too long.");
    const out = new Uint8Array(32);
    out.set(bytes, 32 - bytes.length);
    return out;
  };
  const r = part();
  const s = part();
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}
