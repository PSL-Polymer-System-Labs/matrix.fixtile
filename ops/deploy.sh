#!/usr/bin/env bash
# Pull-only static site deployment. Installed as a root-owned local copy.
set -Eeuo pipefail
umask 027

REPO_URL="https://github.com/PSL-Polymer-System-Labs/matrix.fixtile.git"
SOURCE="/opt/fixtile-matrix-source"
DEST="/var/www/fixtile-matrix"
STATE_DIR="/var/backups/fixtile-matrix"
LOCK="/run/lock/fixtile-matrix-deploy.lock"

exec 9>"$LOCK"
flock -n 9 || exit 0
mkdir -p "$STATE_DIR"

if [[ ! -d "$SOURCE/.git" ]]; then
  git clone --quiet --depth 1 --branch main "$REPO_URL" "$SOURCE"
fi

git -C "$SOURCE" fetch --quiet --depth 1 origin main
git -C "$SOURCE" reset --quiet --hard FETCH_HEAD
revision="$(git -C "$SOURCE" rev-parse HEAD)"
previous="$(cat "$STATE_DIR/deployed.sha" 2>/dev/null || true)"

if [[ "$revision" == "$previous" ]]; then
  echo "Already deployed: ${revision:0:12}"
  exit 0
fi

# Refuse a release that refers to assets not yet tracked by GitHub.
for file in index.html favicon.svg \
  assets/format-square.png assets/format-rectangle.png assets/format-hex.png; do
  if [[ ! -s "$SOURCE/$file" ]]; then
    echo "Deployment blocked: missing $file in GitHub checkout" >&2
    exit 1
  fi
done

mkdir -p "$DEST/assets"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="$STATE_DIR/site-$timestamp.tar.gz"

# Keep an independent restore point outside the Nginx document root.
tar -C "$DEST" -czf "$backup" index.html favicon.svg assets

# Deploy only site content. Do not expose Git metadata or executable ops.
# Intentionally no --delete: preserve server-only files until manually reviewed.
rsync -a --delay-updates "$SOURCE/index.html" "$SOURCE/favicon.svg" "$DEST/"
rsync -a --delay-updates "$SOURCE/assets/" "$DEST/assets/"

# Basic local HTTP smoke test. A redirect to HTTPS is acceptable.
curl --silent --show-error --fail --max-time 10 \
  --header 'Host: matrix.fixtile.ru' \
  --output /dev/null 'http://127.0.0.1/'

printf '%s\n' "$revision" > "$STATE_DIR/deployed.sha"
echo "Deployed ${revision:0:12}; rollback archive: $backup"
