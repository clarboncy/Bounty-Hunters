/**
 * Centralized server error types using Effect.Data.TaggedEnum.
 *
 * All server modules should import and throw these error types
 * instead of plain Error objects or inconsistent string tags.
 */
import * as Data from "effect/Data";

// ─── Error Categories ───────────────────────────────────────────

export class NetworkError extends Data.TaggedError("NetworkError")<{
  readonly message: string;
  readonly statusCode?: number;
  readonly cause?: unknown;
}> {}

export class DatabaseError extends Data.TaggedError("DatabaseError")<{
  readonly message: string;
  readonly query?: string;
  readonly cause?: unknown;
}> {}

export class AuthError extends Data.TaggedError("AuthError")<{
  readonly message: string;
  readonly reason: "invalid_token" | "expired_token" | "missing_token" | "forbidden";
  readonly cause?: unknown;
}> {}

export class GitError extends Data.TaggedError("GitError")<{
  readonly message: string;
  readonly command?: string;
  readonly exitCode?: number;
  readonly cause?: unknown;
}> {}

export class ConfigError extends Data.TaggedError("ConfigError")<{
  readonly message: string;
  readonly field?: string;
  readonly cause?: unknown;
}> {}

export class ValidationError extends Data.TaggedError("ValidationError")<{
  readonly message: string;
  readonly field?: string;
  readonly value?: unknown;
}> {}

export class ProviderError extends Data.TaggedError("ProviderError")<{
  readonly message: string;
  readonly provider?: string;
  readonly statusCode?: number;
  readonly cause?: unknown;
}> {}

export class AttachmentError extends Data.TaggedError("AttachmentError")<{
  readonly message: string;
  readonly path?: string;
  readonly cause?: unknown;
}> {}

// ─── Error Helpers ──────────────────────────────────────────────

/**
 * Map server errors to HTTP status codes.
 */
export function errorToStatusCode(error: unknown): number {
  if (error instanceof AuthError) {
    switch (error.reason) {
      case "missing_token": return 401;
      case "invalid_token": return 401;
      case "expired_token": return 401;
      case "forbidden": return 403;
    }
  }
  if (error instanceof ValidationError) return 400;
  if (error instanceof ConfigError) return 500;
  if (error instanceof DatabaseError) return 500;
  if (error instanceof NetworkError) return error.statusCode ?? 502;
  if (error instanceof GitError) return 500;
  if (error instanceof ProviderError) return error.statusCode ?? 502;
  if (error instanceof AttachmentError) return 400;
  return 500;
}

/**
 * Convert any error to a JSON-safe response body.
 */
export function errorToResponse(error: unknown): { error: string; detail?: string } {
  if (error instanceof Data.TaggedError) {
    return {
      error: error._tag,
      detail: error.message,
    };
  }
  if (error instanceof Error) {
    return { error: "InternalError", detail: error.message };
  }
  return { error: "UnknownError", detail: String(error) };
}

// ─── Exports ────────────────────────────────────────────────────

export const ServerErrors = {
  NetworkError,
  DatabaseError,
  AuthError,
  GitError,
  ConfigError,
  ValidationError,
  ProviderError,
  AttachmentError,
} as const;

export type ServerError =
  | NetworkError
  | DatabaseError
  | AuthError
  | GitError
  | ConfigError
  | ValidationError
  | ProviderError
  | AttachmentError;
