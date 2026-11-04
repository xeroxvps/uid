FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global pnpm@10

WORKDIR /setup
COPY xrixuid.zip /setup/xrixuid.zip
COPY patches/xrixuid-optimized.patch.br.b64 /setup/patch.br.b64
COPY scripts/extract_zip.py /setup/extract_zip.py

# Extract archive source without its embedded .git, local credentials and DB files.
RUN python3 /setup/extract_zip.py /setup/xrixuid.zip /setup/unpacked \
    && mv /setup/unpacked/xrixuid /app \
    && find /app -type d -name data -path "*/api-server/data" -prune -exec rm -rf {} + \
    && node -e "const fs=require('fs'),z=require('zlib');fs.writeFileSync('/setup/optimized.patch',z.brotliDecompressSync(Buffer.from(fs.readFileSync('/setup/patch.br.b64','utf8').trim(),'base64')))" \
    && cd /app && git apply --check /setup/optimized.patch \
    && git apply /setup/optimized.patch

# This helper uses the existing pg dependency from /app/lib/db.
# Run it after HTTP startup so slow database initialization does not block healthchecks.
COPY scripts/bootstrap-db.mjs /app/lib/db/bootstrap-db.mjs

WORKDIR /app
RUN pnpm install --no-frozen-lockfile \
    && PORT=3000 BASE_PATH=/ pnpm run build:deploy \
    && test -s /app/artifacts/uid-web/dist/public/index.html \
    && test -s /app/artifacts/api-server/dist/index.mjs

ENV NODE_ENV=production \
    PORT=3000 \
    WEB_DIST=/app/artifacts/uid-web/dist/public
EXPOSE 3000

CMD ["sh", "-c", "node /app/lib/db/bootstrap-db.mjs & exec node --enable-source-maps /app/artifacts/api-server/dist/index.mjs"]
