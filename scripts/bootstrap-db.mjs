/**
 * Lightweight idempotent PostgreSQL bootstrap for resource-constrained hosts.
 *
 * The Express HTTP process should start immediately. Running drizzle-kit push
 * in the web service's start command blocks the health check on cold DB startup.
 * This script creates the existing minimal event schema in the background.
 *
 * For future schema changes, use an explicit migration instead.
 */
import pg from "pg";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error("[db-bootstrap] DATABASE_URL is missing; cannot initialize database.");
  process.exit(1);
}

const statements = [
  `CREATE TABLE IF NOT EXISTS track_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "timestamp" timestamptz NOT NULL DEFAULT now(),
    "action" text NOT NULL,
    "ip" text NOT NULL DEFAULT 'unknown',
    "ua" text NOT NULL DEFAULT 'unknown',
    "session_id" text NOT NULL DEFAULT 'unknown',
    "entries" jsonb NOT NULL
  )`,
  'CREATE INDEX IF NOT EXISTS track_events_timestamp_idx ON track_events ("timestamp")',
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let initialized = false;

for (let attempt = 1; attempt <= 5; attempt++) {
  const client = new pg.Client({
    connectionString,
    connectionTimeoutMillis: 8000,
    query_timeout: 10000,
  });
  try {
    await client.connect();
    await client.query("BEGIN");
    for (const statement of statements) {
      await client.query(statement);
    }
    await client.query("COMMIT");
    console.log("[db-bootstrap] Event schema ready.");
    initialized = true;
    break;
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch { /* connection may be down */ }
    console.error(
      `[db-bootstrap] Attempt ${attempt}/5 failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    if (attempt < 5) await sleep(attempt * 2000);
  } finally {
    await client.end().catch(() => {});
  }
}

if (!initialized) {
  console.error("[db-bootstrap] Database setup failed; check DATABASE_URL and database availability.");
  process.exitCode = 1;
}
