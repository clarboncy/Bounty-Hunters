/**
 * HTTP response compression middleware — gzip + brotli.
 *
 * Compresses responses larger than 1KB when the client sends Accept-Encoding.
 * Prefers brotli over gzip when both are accepted.
 */
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";
import * as Stream from "effect/Stream";
import { HttpServerResponse, HttpServerRequest } from "effect/unstable/http";
import { zlib } from "node:zlib";

const COMPRESSION_THRESHOLD = 1024; // 1KB minimum

type Encoding = "br" | "gzip";

/**
 * Parse Accept-Encoding header and return the best supported encoding.
 * Prefers brotli > gzip.
 */
function negotiateEncoding(acceptEncoding: string | undefined): Option.Option<Encoding> {
  if (!acceptEncoding) return Option.none();

  const lower = acceptEncoding.toLowerCase();
  const hasBrotli = lower.includes("br");
  const hasGzip = lower.includes("gzip");

  if (hasBrotli) return Option.some("br");
  if (hasGzip) return Option.some("gzip");
  return Option.none();
}

/**
 * Compress a string body using the selected encoding.
 */
function compressBody(body: string, encoding: Encoding): Effect.Effect<Buffer> {
  return Effect.try({
    try: () => {
      if (encoding === "br") {
        return zlib.brotliCompressSync(body);
      }
      return zlib.gzipSync(body);
    },
    catch: (error) => new Error(`Compression failed: ${String(error)}`),
  });
}

/**
 * Wrap an HttpServerResponse with compression if applicable.
 * Checks Accept-Encoding from the request, compresses bodies > 1KB.
 */
export function withCompression(
  response: HttpServerResponse.HttpServerResponse,
  request: HttpServerRequest.HttpServerRequest,
): Effect.Effect<HttpServerResponse.HttpServerResponse> {
  return Effect.gen(function* () {
    const acceptEncoding = request.headers["accept-encoding"] as string | undefined;
    const encoding = negotiateEncoding(acceptEncoding);

    if (Option.isNone(encoding)) return response;

    const enc = Option.getOrThrow(encoding);
    const body = response.body;

    // Only compress string/Uint8Array bodies above threshold
    if (typeof body === "string" && body.length > COMPRESSION_THRESHOLD) {
      const compressed = yield* compressBody(body, enc);
      return response.pipe(
        HttpServerResponse.setHeader("Content-Encoding", enc),
        HttpServerResponse.setHeader("Content-Length", String(compressed.length)),
        HttpServerResponse.setHeader("Vary", "Accept-Encoding"),
      ) as HttpServerResponse.HttpServerResponse;
    }

    return response;
  });
}

export { COMPRESSION_THRESHOLD, negotiateEncoding };
