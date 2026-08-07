import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { createElevenLabsToken } from "../src/elevenlabs";
import type { Env } from "../src/types";

const env: Env = {
  KIMI_API_KEY: "kimi-secret",
  ELEVENLABS_API_KEY: "elevenlabs-secret",
  CLIENT_AUTH_TOKEN: "client-secret",
  TRANSLATION_RATE_LIMITER: {
    limit: async () => ({ success: true })
  },
  TOKEN_RATE_LIMITER: {
    limit: async () => ({ success: true })
  }
};

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("ElevenLabs single-use token connector", () => {
  it("exchanges the server API key for a realtime Scribe token", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({ token: "sutkn_test-token" })
    );
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);

    const result = await createElevenLabsToken(env, "request-1", fetchMock);

    expect(result).toEqual({
      token: "sutkn_test-token",
      expiresInSeconds: 900
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe",
      {
        method: "POST",
        headers: {
          "xi-api-key": "elevenlabs-secret",
          "User-Agent": "MandarinListenerRelay/0.1"
        }
      }
    );
    expect(log.mock.calls.flat().join(" ")).not.toContain("sutkn_test-token");
    expect(log.mock.calls.flat().join(" ")).not.toContain("elevenlabs-secret");
  });

  it("maps provider rate limits without exposing the provider response", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response("account details must not be relayed", { status: 429 })
    );
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);

    await expect(createElevenLabsToken(env, "request-2", fetchMock)).rejects.toMatchObject({
      status: 429,
      code: "rate_limited",
      retryable: true
    });
    expect(warn.mock.calls.flat().join(" ")).not.toContain("account details");
  });

  it("rejects an invalid successful provider response", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ token: "" }));

    await expect(createElevenLabsToken(env, "request-3", fetchMock)).rejects.toMatchObject({
      status: 502,
      code: "invalid_provider_response",
      retryable: true
    });
  });
});

describe("POST /v1/asr/elevenlabs/token", () => {
  it("requires the configured client bearer token", async () => {
    const response = await worker.fetch(
      new Request("https://relay.test/v1/asr/elevenlabs/token", { method: "POST" }),
      env
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "unauthorized" }
    });
  });

  it("returns a no-store token response to an authenticated client", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn<typeof fetch>().mockResolvedValue(Response.json({ token: "sutkn_route-token" }))
    );

    const response = await worker.fetch(
      new Request("https://relay.test/v1/asr/elevenlabs/token", {
        method: "POST",
        headers: { Authorization: "Bearer client-secret" }
      }),
      env
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("X-Request-ID")).toBeTruthy();
    await expect(response.json()).resolves.toEqual({
      token: "sutkn_route-token",
      expiresInSeconds: 900
    });
  });

  it("rejects non-POST requests", async () => {
    const response = await worker.fetch(
      new Request("https://relay.test/v1/asr/elevenlabs/token", {
        headers: { Authorization: "Bearer client-secret" }
      }),
      env
    );

    expect(response.status).toBe(405);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "method_not_allowed" }
    });
  });

  it("does not mint a provider token after the personal rate limit", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    vi.stubGlobal("fetch", fetchMock);
    const limitedEnv: Env = {
      ...env,
      TOKEN_RATE_LIMITER: {
        limit: vi.fn().mockResolvedValue({ success: false })
      }
    };

    const response = await worker.fetch(
      new Request("https://relay.test/v1/asr/elevenlabs/token", {
        method: "POST",
        headers: { Authorization: "Bearer client-secret" }
      }),
      limitedEnv
    );

    expect(response.status).toBe(429);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
