import { RelayError } from "./errors";

const encoder = new TextEncoder();

export function secureEqual(left: string, right: string): boolean {
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let difference = leftBytes.length ^ rightBytes.length;

  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }

  return difference === 0;
}

export function requireAuthorization(request: Request, expectedToken: string): void {
  if (!expectedToken) {
    throw new RelayError(500, "relay_not_configured", "Relay authentication is not configured.");
  }

  const header = request.headers.get("Authorization") ?? "";
  const prefix = "Bearer ";
  const supplied = header.startsWith(prefix) ? header.slice(prefix.length) : "";

  if (!supplied || !secureEqual(supplied, expectedToken)) {
    throw new RelayError(401, "unauthorized", "Invalid relay credentials.");
  }
}

export function jsonResponse(
  value: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {}
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders
    }
  });
}

export function errorResponse(error: unknown, requestId: string): Response {
  if (error instanceof RelayError) {
    return jsonResponse(
      {
        error: {
          code: error.code,
          message: error.message,
          retryable: error.retryable,
          requestId
        }
      },
      error.status,
      { "X-Request-ID": requestId }
    );
  }

  return jsonResponse(
    {
      error: {
        code: "internal_error",
        message: "The relay could not complete the request.",
        retryable: true,
        requestId
      }
    },
    500,
    { "X-Request-ID": requestId }
  );
}
