import express, { type Request, type Response, type NextFunction } from "express";
import fbRouter from "./routes/fb";

// Isolated fetch-only service. It does not load admin routes or the database.
const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "64kb" }));
const secret = process.env.FETCH_BACKEND_TOKEN ?? "";
if (secret.length < 24) throw new Error("FETCH_BACKEND_TOKEN must contain at least 24 characters");

const port = Number(process.env.PORT ?? "3000");
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid PORT");

app.get("/api/healthz", (_req: Request, res: Response) => {
  res.json({ status: "ok", service: "xrixuid-fetch" });
});

// Bounded FIFO for concurrent batches. Reject overload; don't rotate sessions.
const queue: Array<() => void> = [];
let active = 0;
const MAX_ACTIVE = 1;
const MAX_QUEUED = 8;
function drain() {
  while (active < MAX_ACTIVE && queue.length > 0) queue.shift()?.();
}

function gate(req: Request, res: Response, next: NextFunction): void {
  if (req.header("x-fetch-backend-token") !== secret) {
    res.status(401).json({ success: false, error: "Unauthorized" });
    return;
  }
  if (req.method !== "POST" || req.path !== "/uid/fetch") {
    next();
    return;
  }
  if (req.body && typeof req.body === "object") delete req.body.cookie;
  const uids = req.body?.uids;
  if (!Array.isArray(uids) || uids.length > 120 ||
    uids.some((item: unknown) => !item || typeof item !== "object" ||
      !/^\d{5,25}$/.test(String((item as { uid?: unknown }).uid ?? "")))) {
    res.status(400).json({ success: false, error: "Expected up to 120 numeric UIDs" });
    return;
  }
  let started = false;
  let released = false;
  const release = () => {
    if (released || !started) return;
    released = true;
    active--;
    drain();
  };
  const run = () => {
    if (res.writableEnded || res.destroyed) { drain(); return; }
    started = true;
    active++;
    res.once("finish", release);
    res.once("close", release);
    next();
  };
  if (active < MAX_ACTIVE && queue.length === 0) {
    run();
  } else if (queue.length >= MAX_QUEUED) {
    res.status(429).set("Retry-After", "10").json({ success: false, error: "Service busy" });
  } else {
    queue.push(run);
    res.once("close", () => {
      if (!started) {
        const index = queue.indexOf(run);
        if (index >= 0) queue.splice(index, 1);
      }
    });
  }
}

app.use("/api/fb", gate, fbRouter);
app.use((_req: Request, res: Response) => { res.status(404).json({ error: "Not found" }); });

app.listen(port, "0.0.0.0", () => {
  console.log(`[xrixuid-fetch] listening on port ${port}`);
});
