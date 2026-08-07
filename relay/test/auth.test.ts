import { describe, expect, it } from "vitest";
import { requireAuthorization, secureEqual } from "../src/http";
import worker from "../src/index";
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

describe("relay authorization", () => {
  it("compares secrets without early-returning on content", () => {
    expect(secureEqual("abc", "abc")).toBe(true);
    expect(secureEqual("abc", "abd")).toBe(false);
    expect(secureEqual("abc", "abcd")).toBe(false);
  });

  it("accepts the configured bearer token", () => {
    const request = new Request("https://relay.test/v1/translate", {
      headers: { Authorization: "Bearer private-token" }
    });
    expect(() => requireAuthorization(request, "private-token")).not.toThrow();
  });

  it("rejects a missing or wrong token", () => {
    const request = new Request("https://relay.test/v1/translate");
    expect(() => requireAuthorization(request, "private-token")).toThrowError(
      /Invalid relay credentials/
    );
  });
});

describe("GET /v1/auth/check", () => {
  it("verifies both relay identity and the client credential", async () => {
    const response = await worker.fetch(
      new Request("https://relay.test/v1/auth/check", {
        headers: { Authorization: "Bearer client-secret" }
      }),
      env
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    await expect(response.json()).resolves.toEqual({
      status: "ok",
      service: "mandarin-listener-relay",
      authenticated: true
    });
  });

  it("rejects an invalid client credential", async () => {
    const response = await worker.fetch(
      new Request("https://relay.test/v1/auth/check", {
        headers: { Authorization: "Bearer wrong" }
      }),
      env
    );
    expect(response.status).toBe(401);
  });
});
