/**
 * SQLite optimization pragmas for WAL mode + connection pooling.
 *
 * Applied on database initialization to improve concurrent read/write performance.
 */
import * as Effect from "effect/Effect";
import { SqlClient } from "@effect/sql";
import { EffectPool } from "@effect/sql-sqlite-bun";

/**
 * PRAGMA statements applied on every connection in the pool.
 * These are safe to run repeatedly — SQLite ignores no-ops.
 */
const PRAGMAS = [
  "PRAGMA journal_mode=WAL",
  "PRAGMA busy_timeout=5000",
  "PRAGMA synchronous=NORMAL",
  "PRAGMA foreign_keys=ON",
  "PRAGMA cache_size=-64000", // 64MB cache
  "PRAGMA temp_store=MEMORY",
] as const;

/**
 * Apply optimization PRAGMAs to a SQLite connection.
 * Call this after pool creation, before serving requests.
 */
export const applySqlitePragmas = Effect.gen(function* () {
  const sql = yield* SqlClient.SqlClient;
  for (const pragma of PRAGMAS) {
    yield* sql`PRAGMA ${pragma}`.pipe(
      Effect.catchAll((error) =>
        Effect.logWarning(`SQLite PRAGMA failed: ${pragma} — ${String(error)}`),
      ),
    );
  }
  yield* Effect.logInfo("SQLite PRAGMAS applied: WAL mode, busy_timeout=5000, synchronous=NORMAL");
});

/**
 * Create a pooled SQLite client with WAL mode enabled.
 * Wraps EffectPool with PRAGMA initialization.
 */
export const makePooledSqlite = EffectPool.make({
  filename: ":memory:", // overridden by config at runtime
  poolConfig: {
    min: 2,
    max: 10,
    acquireTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
  },
}).pipe(
  Effect.tap(() => applySqlitePragmas),
);

export { PRAGMAS };
