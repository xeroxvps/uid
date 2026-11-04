#!/data/data/com.termux/files/usr/bin/bash
# Manual fallback when GitHub Actions cannot start its runner.
set -Eeuo pipefail
REPO="https://github.com/xeroxvps/uid.git"
TARGET="$HOME/uid"
if [[ ! -d "$TARGET/.git" ]]; then
  git clone "$REPO" "$TARGET"
fi
cd "$TARGET"
git pull --ff-only origin main
python scripts/extract_zip.py xrixuid.zip unpacked
git add -A unpacked
if git diff --cached --quiet; then
  echo "[OK] Extracted files already match the latest ZIP."
else
  git -c user.name="XeroxVPS" -c user.email="actions@users.noreply.github.com" commit -m "Unpack xrixuid.zip source"
  echo "Pushing to GitHub. Configure GitHub SSH/PAT authentication if prompted."
  git push origin main
fi
echo "[OK] Source extracted and repository synced."
