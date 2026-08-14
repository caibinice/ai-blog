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
systemctl --no-pager --full status \
  nginx ai-quant-api crossborder-trend enterprise-ai-cockpit 2>&1 \
  | grep -E '^(●| +Active:| +Main PID:| +Memory:| +CPU:)' || true
ss -lntp | grep -E ':(8000|8080|8090) ' || true
free -h
journalctl -u enterprise-ai-cockpit.service -n 35 --no-pager 2>&1
""",
                root=True,
                timeout=60,
            )
        )
    finally:
        remote.close()


if __name__ == "__main__":
    main()
