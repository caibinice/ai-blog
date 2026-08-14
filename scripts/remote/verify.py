from __future__ import annotations

import sys
from pathlib import Path

QUANT_ROOT = Path(__file__).resolve().parents[3] / "ai-quantitative-trading"
sys.path.insert(0, str(QUANT_ROOT / "scripts" / "remote"))
from remote_client import RemoteClient  # noqa: E402


def main() -> None:
    remote = RemoteClient()
    try:
        print(
            remote.run(
                """
nginx -t
systemctl is-active nginx ai-quant-api ai-quant-worker crossborder-trend enterprise-ai-cockpit
systemctl show crossborder-trend enterprise-ai-cockpit \
  -p Id -p MemoryCurrent -p MemoryHigh -p MemoryMax -p CPUQuotaPerSecUSec
ss -lntp | grep -E ':(8000|8080|8090) '
/usr/local/bin/java17 -version 2>&1 | head -n 1
curl -fsS http://127.0.0.1:8000/api/health >/dev/null
curl -fsS http://127.0.0.1:8090/api/health >/dev/null
curl -fsS http://127.0.0.1:8080/api/health >/dev/null
for url in \
  https://openai.com/news/rss.xml \
  https://deepmind.google/blog/rss.xml \
  https://huggingface.co/blog/feed.xml; do
  curl -4 -L --max-time 8 -o /dev/null -sS \
    -w '%{http_code} %{time_total} %{url_effective}\\n' "$url" || true
done
curl -4 -L --max-time 30 -o /dev/null -sS \
  -w '%{http_code} %{time_total} %{url_effective}\\n' \
  https://huggingface.co/blog/feed.xml || true
""",
                root=True,
                timeout=90,
            )
        )
    finally:
        remote.close()


if __name__ == "__main__":
    main()
