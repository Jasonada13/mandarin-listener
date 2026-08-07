import { RelayError } from "./errors";
import type { Env } from "./types";

const TOKEN_URL = "https://api.elevenlabs.io/v1/single-use-token/realtime_scribe";
const TOKEN_LIFETIME_SECONDS = 900;

interface ElevenLabsTokenResponse {
  token?: unknown;
}

export interface ElevenLabsTokenResult {
  token: string;
  expiresInSeconds: number;
}

export async function createElevenLabsToken(
  env: Env,
  requestId: string,
  fetchImplementation: typeof fetch = fetch
): Promise<ElevenLabsTokenResult> {
  if (!env.ELEVENLABS_API_KEY) {
    throw new RelayError(
      500,
      "relay_not_configured",
      "ElevenLabs speech recognition is not configured."
    );
  }

  const startedAt = Date.now();
  let response: Response;
  try {
    response = await fetchImplementation(TOKEN_URL, {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "User-Agent": "MandarinListenerRelay/0.1"
      }
    });
  } catch {
    console.warn(
      JSON.stringify({
        event: "elevenlabs_token_error",
        request_id: requestId,
        code: "network_error",
        duration_ms: Date.now() - startedAt
      })
    );
    throw new RelayError(
      502,
      "asr_unavailable",
      "ElevenLabs speech recognition is unavailable.",
      true
    );
  }

  const latencyMs = Date.now() - startedAt;
  if (!response.ok) {
    console.warn(
      JSON.stringify({
        event: "elevenlabs_token_error",
        request_id: requestId,
        status: response.status,
        duration_ms: latencyMs
      })
    );
    throw new RelayError(
      response.status === 429 ? 429 : 502,
      response.status === 429 ? "rate_limited" : "asr_unavailable",
      response.status === 429
        ? "ElevenLabs is rate limiting speech recognition requests."
        : "ElevenLabs speech recognition is unavailable.",
      true
    );
  }

  let payload: ElevenLabsTokenResponse;
  try {
    payload = (await response.json()) as ElevenLabsTokenResponse;
  } catch {
    throw new RelayError(
      502,
      "invalid_provider_response",
      "ElevenLabs returned an invalid token.",
      true
    );
  }

  if (
    typeof payload.token !== "string" ||
    !payload.token.trim() ||
    payload.token.length > 4_096
  ) {
    throw new RelayError(
      502,
      "invalid_provider_response",
      "ElevenLabs returned an invalid token.",
      true
    );
  }

  console.log(
    JSON.stringify({
      event: "elevenlabs_token_success",
      request_id: requestId,
      status: response.status,
      duration_ms: latencyMs
    })
  );

  return {
    token: payload.token,
    expiresInSeconds: TOKEN_LIFETIME_SECONDS
  };
}
