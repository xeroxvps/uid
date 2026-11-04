import { Router, type Request, type Response } from "express";

// Main site's server-side proxy; never forwards browser session cookies.
const proxy = Router();
const upstreamBase = process.env.FETCH_BACKEND_URL ?? "";
const secret = process.env.FETCH_BACKEND_TOKEN ?? "";
if (upstreamBase && secret.length < 24) {
  throw new Error("FETCH_BACKEND_TOKEN must be set when FETCH_BACKEND_URL is configured");
}

proxy.use(async (req: Request, res: Response) => {
  if (req.method !== "GET" && req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  const path = req.originalUrl.split("?")[0];
  const allowed = (req.method === "POST" && path === "/api/fb/uid/fetch") ||
    (req.method === "GET" && (path === "/api/fb/health" ||
      path === "/api/fb/" || /^\/api\/fb\/proxy\/pic\/\d{5,25}$/.test(path)));
  if (!allowed) { res.status(404).json({ error: "Unknown endpoint" }); return; }

  let payload: string | undefined;
  if (req.method === "POST") {
    const uids = req.body?.uids;
    if (!Array.isArray(uids) || uids.length > 120) {
      res.status(400).json({ error: "Invalid UID batch" });
      return;
    }
    payload = JSON.stringify({ uids: uids.map((item: {uid?: unknown}) => ({
      uid: String(item?.uid ?? ""),
    })) });
  }

  try {
    const base = new URL(upstreamBase);
    if (base.protocol !== "https:" &&
      !(base.protocol === "http:" && ["localhost", "127.0.0.1"].includes(base.hostname))) {
      throw new Error("Backend URL must use HTTPS or localhost HTTP");
    }
    const url = new URL(req.originalUrl, base);
    const response = await fetch(url, {
      method: req.method,
      headers: {
        "x-fetch-backend-token": secret,
        ...(payload ? { "content-type": "application/json" } : {}),
      },
      body: payload,
      signal: AbortSignal.timeout(45000),
      redirect: "error",
    });
    const contentType = response.headers.get("content-type") ?? "application/json";
    const contentLength = Number(response.headers.get("content-length") ?? "0");
    if (contentLength > 8 * 1024 * 1024) {
      res.status(502).json({ error: "Backend response too large" });
      return;
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length > 8 * 1024 * 1024) {
      res.status(502).json({ error: "Backend response too large" });
      return;
    }
    res.status(response.status).set("Content-Type", contentType);
    const cache = response.headers.get("cache-control");
    res.set("Cache-Control", cache && contentType.startsWith("image/") ? cache : "no-store");
    res.send(buffer);
  } catch (error) {
    console.error("[fetch-proxy] upstream unavailable", error instanceof Error ? error.message : String(error));
    res.status(502).json({ success: false, error: "Fetch service unavailable" });
  }
});

export default proxy;
