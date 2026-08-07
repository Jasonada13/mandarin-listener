import { createElevenLabsToken } from "./elevenlabs";
import { RelayError } from "./errors";
import { errorResponse, jsonResponse, requireAuthorization } from "./http";
import {
  streamPreviewWithKimi,
  translateWithKimi,
  validateTranslationRequest
} from "./kimi";
import type { Env } from "./types";

async function readJSON(request: Request): Promise<unknown> {
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new RelayError(415, "unsupported_media_type", "Content-Type must be application/json.");
  }

  try {
    return await request.json();
  } catch {
    throw new RelayError(400, "invalid_json", "Request body is not valid JSON.");
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestId = crypto.randomUUID();
    const url = new URL(request.url);

    try {
      if (url.pathname === "/health") {
        if (request.method !== "GET") {
          throw new RelayError(405, "method_not_allowed", "Use GET for this endpoint.");
        }
        return jsonResponse(
          {
            status: "ok",
            service: "mandarin-listener-relay",
            model: env.KIMI_MODEL || "kimi-k2.6"
          },
          200,
          { "X-Request-ID": requestId }
        );
      }

      requireAuthorization(request, env.CLIENT_AUTH_TOKEN);

      if (url.pathname === "/v1/auth/check") {
        if (request.method !== "GET") {
          throw new RelayError(405, "method_not_allowed", "Use GET for this endpoint.");
        }
        return jsonResponse(
          {
            status: "ok",
            service: "mandarin-listener-relay",
            authenticated: true
          },
          200,
          { "X-Request-ID": requestId }
        );
      }

      if (url.pathname === "/v1/translate") {
        if (request.method !== "POST") {
          throw new RelayError(405, "method_not_allowed", "Use POST for this endpoint.");
        }
        const { success } = await env.TRANSLATION_RATE_LIMITER.limit({
          key: "personal-client"
        });
        if (!success) {
          throw new RelayError(
            429,
            "relay_rate_limited",
            "The personal translation request limit was reached.",
            true
          );
        }
        const input = validateTranslationRequest(await readJSON(request));
        const result = await translateWithKimi(input, env, requestId);
        return jsonResponse(result, 200, { "X-Request-ID": requestId });
      }

      if (url.pathname === "/v1/translate/preview") {
        if (request.method !== "POST") {
          throw new RelayError(405, "method_not_allowed", "Use POST for this endpoint.");
        }
        const { success } = await env.TRANSLATION_RATE_LIMITER.limit({
          key: "personal-client"
        });
        if (!success) {
          throw new RelayError(
            429,
            "relay_rate_limited",
            "The personal translation request limit was reached.",
            true
          );
        }
        const input = validateTranslationRequest(await readJSON(request));
        const stream = await streamPreviewWithKimi(
          input,
          env,
          requestId,
          fetch,
          request.signal
        );
        const headers = new Headers(stream.headers);
        headers.set("X-Request-ID", requestId);
        return new Response(stream.body, {
          status: stream.status,
          headers
        });
      }

      if (url.pathname === "/v1/asr/elevenlabs/token") {
        if (request.method !== "POST") {
          throw new RelayError(405, "method_not_allowed", "Use POST for this endpoint.");
        }
        const { success } = await env.TOKEN_RATE_LIMITER.limit({
          key: "personal-client"
        });
        if (!success) {
          throw new RelayError(
            429,
            "relay_rate_limited",
            "The personal speech-session request limit was reached.",
            true
          );
        }
        const result = await createElevenLabsToken(env, requestId);
        return jsonResponse(result, 200, { "X-Request-ID": requestId });
      }

      throw new RelayError(404, "not_found", "Endpoint not found.");
    } catch (error) {
      if (!(error instanceof RelayError)) {
        console.error(
          JSON.stringify({
            event: "relay_error",
            request_id: requestId,
            code: "internal_error"
          })
        );
      }
      return errorResponse(error, requestId);
    }
  }
} satisfies ExportedHandler<Env>;
