"""Update only the Nginx configuration, validating before it takes effect.

The full deploy.py rebuilds both Java projects, restarts services and starts the
resource sampler. When the only change is Nginx config, that is far more blast
radius than the change deserves. This script installs the new config, runs
`nginx -t` while it is in place, and reloads only if the test passes; any failure
restores the previous config and re-tests it, so a bad config can never be left
behind for the next restart to pick up.
"""

from __future__ import annotations

import sys
from pathlib import Path

BLOG_ROOT = Path(__file__).resolve().parents[2]
QUANT_ROOT = BLOG_ROOT.parent / "ai-quantitative-trading"
sys.path.insert(0, str(QUANT_ROOT / "scripts" / "remote"))
from remote_client import RemoteClient  # noqa: E402

REMOTE_SCRIPT = r"""
set -euo pipefail

backup=/root/nginx-backup-$(date +%Y%m%d%H%M%S)
mkdir -p "$backup"
cp /etc/nginx/nginx.conf "$backup/nginx.conf"
cp /etc/nginx/conf.d/ai-platform.conf "$backup/ai-platform.conf"
if [ -f /etc/nginx/snippets/ai-platform-routes.conf ]; then
  cp /etc/nginx/snippets/ai-platform-routes.conf "$backup/ai-platform-routes.conf"
  touch "$backup/had-ai-platform-routes"
fi
echo "Previous config saved to $backup"

restore() {
  echo 'Config test failed. Restoring previous configuration.'
  cp "$backup/nginx.conf" /etc/nginx/nginx.conf
  cp "$backup/ai-platform.conf" /etc/nginx/conf.d/ai-platform.conf
  if [ -f "$backup/had-ai-platform-routes" ]; then
    install -m 644 "$backup/ai-platform-routes.conf" /etc/nginx/snippets/ai-platform-routes.conf
  else
    rm -f /etc/nginx/snippets/ai-platform-routes.conf
  fi
  nginx -t
  echo 'Previous configuration restored and verified. Nginx was not reloaded.'
  exit 1
}

install -m 644 /tmp/ai-platform-nginx.conf /etc/nginx/nginx.conf
install -m 644 /tmp/ai-platform.conf /etc/nginx/conf.d/ai-platform.conf
install -d -m 755 /etc/nginx/snippets
install -m 644 /tmp/ai-platform-routes.conf /etc/nginx/snippets/ai-platform-routes.conf

nginx -t || restore

systemctl reload nginx
systemctl is-active --quiet nginx || restore

rm -f /tmp/ai-platform-nginx.conf /tmp/ai-platform.conf /tmp/ai-platform-routes.conf
echo 'Nginx configuration updated and reloaded.'
"""


def main() -> None:
    remote = RemoteClient()
    try:
        remote.upload_file(
            BLOG_ROOT / "deploy" / "nginx" / "nginx.conf",
            "/tmp/ai-platform-nginx.conf",
            0o644,
        )
        remote.upload_file(
            BLOG_ROOT / "deploy" / "nginx" / "ai-platform.conf",
            "/tmp/ai-platform.conf",
            0o644,
        )
        remote.upload_file(
            BLOG_ROOT / "deploy" / "nginx" / "ai-platform-routes.conf",
            "/tmp/ai-platform-routes.conf",
            0o644,
        )
        remote.upload_bytes(REMOTE_SCRIPT.encode(), "/tmp/update-nginx.sh", 0o700)
        remote.run("/bin/bash /tmp/update-nginx.sh", root=True, timeout=180)
    finally:
        remote.close()


if __name__ == "__main__":
    main()
