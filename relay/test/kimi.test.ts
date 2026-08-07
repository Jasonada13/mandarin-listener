import { describe, expect, it, vi } from "vitest";
import {
  buildKimiPreviewRequest,
  buildKimiRequest,
  parseKimiTranslation,
  streamPreviewWithKimi,
  translateWithKimi,
  validateTranslationRequest
} from "../src/kimi";
import type { Env } from "../src/types";

const request = {
  sessionId: "session-1",
  utteranceId: "utterance-1",
  sourceText: "这个周末我们要不要一起去吃火锅？",
  context: [{ sourceText: "你周末有空吗？", displayTranslation: "Are you free this weekend?" }]
};

const env: Env = {
  KIMI_API_KEY: "secret",
  KIMI_MODEL: "kimi-k2.6",
  ELEVENLABS_API_KEY: "unused",
  CLIENT_AUTH_TOKEN: "unused",
  TRANSLATION_RATE_LIMITER: {
    limit: async () => ({ success: true })
  },
  TOKEN_RATE_LIMITER: {
    limit: async () => ({ success: true })
  }
};

describe("Kimi translation connector", () => {
  it("validates and trims the client request", () => {
    const result = validateTranslationRequest({ ...request, sourceText: ` ${request.sourceText} ` });
    expect(result.sourceText).toBe(request.sourceText);
    expect(result.context).toHaveLength(1);
  });

  it("rejects oversized context", () => {
    expect(() =>
      validateTranslationRequest({
        ...request,
        context: Array.from({ length: 9 }, () => ({ sourceText: "你好" }))
      })
    ).toThrowError(/at most 8 turns/);
  });

  it("builds a low-latency structured request", () => {
    const body = buildKimiRequest(request, "kimi-k2.6") as Record<string, unknown>;
    expect(body.thinking).toEqual({ type: "disabled" });
    expect(body).not.toHaveProperty("temperature");
    expect(body.max_completion_tokens).toBe(80);
    expect(body.response_format).toMatchObject({ type: "json_schema" });
    expect(body.prompt_cache_key).toBe("session-1");
  });

  it("builds a streaming low-latency preview request", () => {
    const body = buildKimiPreviewRequest(request, "kimi-k2.6") as Record<
      string,
      unknown
    >;
    expect(body.thinking).toEqual({ type: "disabled" });
    expect(body.stream).toBe(true);
    expect(body.max_completion_tokens).toBe(48);
    expect(body.prompt_cache_key).toBe("session-1");
    expect(body).not.toHaveProperty("response_format");
  });

  it("rejects overlong spoken output instead of truncating critical facts", () => {
    const words = Array.from({ length: 25 }, (_, index) => `word${index}`).join(" ");
    expect(() =>
      parseKimiTranslation(
        JSON.stringify({
          display_translation: "Would you like to get hotpot this weekend?",
          spoken_translation: words
        })
      )
    ).toThrowError(
      /overlong spoken translation/
    );
  });

  it("maps a successful provider response without leaking source text to logs", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(
        JSON.stringify({
          model: "kimi-k2.6",
          choices: [
            {
              message: {
                content: JSON.stringify({
                  display_translation: "Would you like to get hotpot this weekend?",
                  spoken_translation: "Fancy hotpot together this weekend?"
                })
              }
            }
          ],
          usage: { prompt_tokens: 30, completion_tokens: 12 }
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    );
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);

    const result = await translateWithKimi(request, env, "request-1", fetchMock);

    expect(result.utteranceId).toBe("utterance-1");
    expect(result.spokenTranslation).toContain("hotpot");
    expect(fetchMock).toHaveBeenCalledOnce();
    expect(log.mock.calls.flat().join(" ")).not.toContain(request.sourceText);
    log.mockRestore();
  });

  it("passes through Kimi preview SSE without buffering or logging source text", async () => {
    const providerBody = [
      'data: {"choices":[{"delta":{"content":"Would"}}]}',
      'data: {"choices":[{"delta":{"content":" you like hotpot?"}}]}',
      "data: [DONE]",
      ""
    ].join("\n\n");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      new Response(providerBody, {
        status: 200,
        headers: { "Content-Type": "text/event-stream" }
      })
    );
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);

    const response = await streamPreviewWithKimi(
      request,
      env,
      "preview-request-1",
      fetchMock
    );

    expect(response.headers.get("Content-Type")).toContain("text/event-stream");
    expect(await response.text()).toBe(providerBody);
    expect(fetchMock).toHaveBeenCalledOnce();
    const providerRequest = JSON.parse(
      String(fetchMock.mock.calls[0]?.[1]?.body)
    ) as Record<string, unknown>;
    expect(providerRequest.stream).toBe(true);
    expect(log.mock.calls.flat().join(" ")).not.toContain(request.sourceText);
    log.mockRestore();
  });
});
