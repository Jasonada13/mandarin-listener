export interface Env {
  KIMI_API_KEY: string;
  KIMI_MODEL?: string;
  ELEVENLABS_API_KEY: string;
  CLIENT_AUTH_TOKEN: string;
  TRANSLATION_RATE_LIMITER: RateLimit;
  TOKEN_RATE_LIMITER: RateLimit;
}

export interface TranslationContextTurn {
  sourceText: string;
  displayTranslation?: string;
  timestamp?: string;
}

export interface TranslationRequest {
  sessionId: string;
  utteranceId: string;
  sourceText: string;
  context: TranslationContextTurn[];
}

export interface TranslationResult {
  utteranceId: string;
  displayTranslation: string;
  spokenTranslation: string;
  model: string;
  latencyMs: number;
}
