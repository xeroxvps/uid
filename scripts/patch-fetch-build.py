#!/usr/bin/env python3
"""Integrate separate fetching entrypoint and optional frontend API proxy."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
app = root / "artifacts/api-server/src/app.ts"
build = root / "artifacts/api-server/build.mjs"

def replace_once(file: Path, old: str, new: str) -> None:
    source = file.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise SystemExit(f"Unexpected source version: {file} marker count {source.count(old)}")
    file.write_text(source.replace(old, new), encoding="utf-8")

replace_once(
    app,
    'import fbRouter from "./routes/fb";',
    'import fbRouter from "./routes/fb";\nimport fetchProxy from "./fetch-proxy";',
)
replace_once(
    app,
    'app.use("/api/fb", fbRouter);',
    'app.use("/api/fb", process.env.FETCH_BACKEND_URL ? fetchProxy : fbRouter);',
)
replace_once(
    build,
    'entryPoints: [path.resolve(artifactDir, "src/index.ts")],',
    'entryPoints: [path.resolve(artifactDir, "src/index.ts"), path.resolve(artifactDir, "src/fetch-server.ts")],',
)
print("Applied isolated fetch service entrypoint and API proxy")
