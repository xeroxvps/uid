#!/usr/bin/env python3
"""Reject login/challenge HTML and invalid image responses in XRIXUID's FB route.

Applies only to the known optimized source version. Fail rather than changing
unexpected source code; requires no authenticated requests or session rotation.
"""
from pathlib import Path
import sys

path = Path(sys.argv[1])
s = path.read_text(encoding='utf-8')

steps = [
    (
        '''    if (!res.ok) return null;
    return await res.text();''',
        '''    if (!res.ok) return null;
    // Redirected login/checkpoint pages are never profile data.
    const finalPath = new URL(res.url).pathname.toLowerCase();
    if (/^\\/(?:login|checkpoint|recover|reg|two_step_verification)(?:\\/|$)/.test(finalPath)) {
      return null;
    }
    const mediaType = (res.headers.get("content-type") ?? "").toLowerCase();
    if (!mediaType.includes("text/html") && !mediaType.includes("application/xhtml+xml")) {
      return null;
    }
    const html = await res.text();
    const $ = load(html);
    const pageTitle = $("title").first().text().trim().toLowerCase();
    if (/(?:log\\s*in|sign\\s*up|create an account|checkpoint|verify your identity|session expired)/i.test(pageTitle)) {
      return null;
    }
    // Recognize actual login forms; avoid mistaking their placeholders for profile details.
    if ($('input[name="email"]').length > 0 && $('input[name="pass"]').length > 0) {
      return null;
    }
    return html;'''
    ),
    (
        '''    const contentType = imgRes.headers.get("content-type") ?? "image/jpeg";
    res.set("Content-Type", contentType);''',
        '''    const contentType = (imgRes.headers.get("content-type") ?? "").toLowerCase();
    // CDN failures sometimes redirect to HTML login pages with HTTP 200.
    // Never serve HTML or other non-images as avatar data.
    if (!/^image\\/(?:jpeg|png|webp|gif|avif)(?:;|$)/.test(contentType)) {
      cdnCache.delete(uid);
      res.status(502).json({ error: "Profile image unavailable" });
      return;
    }
    res.set("Content-Type", contentType);'''
    ),
]

for before, after in steps:
    count = s.count(before)
    if count != 1:
        raise SystemExit(f'Expected exactly one source marker, found {count}: {before[:65]}')
    s = s.replace(before, after, 1)

path.write_text(s, encoding='utf-8')
print('Applied login-page and image-response validation')
