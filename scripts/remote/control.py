from __future__ import annotations

import argparse
import sys
from pathlib import Path

QUANT_ROOT = Path(__file__).resolve().parents[3] / "ai-quantum"
sys.path.insert(0, str(QUANT_ROOT / "scripts" / "remote"))
from remote_client import RemoteClient  # noqa: E402

SERVICES = {
    "cross": "crossborder-trend.service",
    "cockpit": "enterprise-ai-cockpit.service",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["start", "stop", "restart"])
    parser.add_argument("target", choices=SERVICES)
    args = parser.parse_args()
    remote = RemoteClient()
    try:
        remote.run(
            f"systemctl {args.action} {SERVICES[args.target]}",
            root=True,
            timeout=60,
        )
    finally:
        remote.close()


if __name__ == "__main__":
    main()
