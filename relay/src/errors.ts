export class RelayError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly retryable = false
  ) {
    super(message);
    this.name = "RelayError";
  }
}
