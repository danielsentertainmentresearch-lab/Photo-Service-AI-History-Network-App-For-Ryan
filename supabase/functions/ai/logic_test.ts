import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import {
  BadRequest,
  base64UrlToBytes,
  capEffort,
  configFrom,
  dayKey,
  derToRawSignature,
  shapeRequest,
  splitAdMobQuery,
  TASKS,
} from "./logic.ts";

const config = configFrom(() => undefined);

Deno.test("defaults: Opus everywhere, high effort cap, 20 credits a day", () => {
  assertEquals(config.models.describe, "claude-opus-5-5");
  assertEquals(config.models.label, "claude-opus-5-5");
  assertEquals(config.maxEffort, "high");
  assertEquals(config.dailyCredits, 20);
  assertEquals(config.adsEnabled, false);
});

Deno.test("per-task model and limits come from the environment", () => {
  const env: Record<string, string> = {
    AI_MODEL: "claude-opus-5-5",
    AI_MODEL_LABEL: "claude-sonnet-5-5",
    AI_MAX_EFFORT: "medium",
    AI_DAILY_CREDITS: "30",
    ADS_ENABLED: "true",
  };
  const c = configFrom((n) => env[n]);
  assertEquals(c.models.label, "claude-sonnet-5-5");
  assertEquals(c.models.describe, "claude-opus-5-5");
  assertEquals(c.maxEffort, "medium");
  assertEquals(c.dailyCredits, 30);
  assertEquals(c.adsEnabled, true);
});

Deno.test("the server decides model, effort cap and output length", () => {
  const shaped = shapeRequest("describe", {
    model: "something-expensive",
    max_tokens: 999999,
    thinking: { type: "enabled", budget_tokens: 50000 },
    output_config: { effort: "max", format: { type: "json_schema" } },
    system: "instructions",
    messages: [{ role: "user", content: "hi" }],
    tools: [{ name: "x" }],
    speed: "fast",
  }, config);
  assertEquals(shaped, {
    model: "claude-opus-5-5",
    max_tokens: TASKS.describe.maxTokens,
    thinking: { type: "adaptive" },
    output_config: { effort: "high", format: { type: "json_schema" } },
    fallbacks: "default",
    messages: [{ role: "user", content: "hi" }],
    system: "instructions",
  });
});

Deno.test("smaller requests and lower effort pass through unchanged", () => {
  const shaped = shapeRequest("label", {
    max_tokens: 1000,
    output_config: { effort: "low" },
    messages: [{ role: "user", content: "hi" }],
  }, config);
  assertEquals(shaped.max_tokens, 1000);
  assertEquals(shaped.output_config, { effort: "low" });
  assertEquals("system" in shaped, false);
});

Deno.test("a request without messages is rejected", () => {
  assertThrows(() => shapeRequest("label", {}, config), BadRequest);
  assertThrows(() => shapeRequest("label", null, config), BadRequest);
});

Deno.test("effort is capped, unknown effort becomes medium", () => {
  assertEquals(capEffort("xhigh", "high"), "high");
  assertEquals(capEffort("low", "high"), "low");
  assertEquals(capEffort("nonsense", "high"), "medium");
  assertEquals(capEffort(undefined, "low"), "low");
});

Deno.test("the allowance day is the UTC date", () => {
  assertEquals(dayKey(new Date("2026-10-05T23:59:59Z")), "2026-10-05");
});

Deno.test("AdMob callbacks split into the signed part and its signature", () => {
  const q =
    "?ad_network=5450213213286189855&reward_amount=1&transaction_id=t1&user_id=u1&signature=MEUC&key_id=3335741209";
  assertEquals(splitAdMobQuery(q), {
    message:
      "ad_network=5450213213286189855&reward_amount=1&transaction_id=t1&user_id=u1",
    signature: "MEUC",
    keyId: "3335741209",
  });
  assertEquals(splitAdMobQuery("?user_id=u1"), null);
});

Deno.test("a DER signature converts to the raw form Web Crypto verifies", async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const data = new TextEncoder().encode("ad_network=1&user_id=u1");
  const raw = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      pair.privateKey,
      data,
    ),
  );
  const der = rawToDer(raw);
  const back = derToRawSignature(der);
  assertEquals(back, raw);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    back,
    data,
  );
  assertEquals(ok, true);
});

Deno.test("base64url decodes without padding", () => {
  assertEquals(base64UrlToBytes("_-8"), new Uint8Array([255, 239]));
});

/** Encodes r||s as DER, the way AdMob sends signatures. */
function rawToDer(raw: Uint8Array): Uint8Array {
  const int = (bytes: Uint8Array) => {
    let b = bytes;
    while (b.length > 1 && b[0] === 0 && !(b[1] & 0x80)) b = b.slice(1);
    if (b[0] & 0x80) b = Uint8Array.from([0, ...b]);
    return [0x02, b.length, ...b];
  };
  const body = [...int(raw.slice(0, 32)), ...int(raw.slice(32))];
  return Uint8Array.from([0x30, body.length, ...body]);
}
