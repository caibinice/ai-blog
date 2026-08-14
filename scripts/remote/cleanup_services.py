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
set -euo pipefail
if [[ -n "$(atq 2>/dev/null || true)" ]]; then
  echo 'atd has queued work; refusing cleanup' >&2
  exit 1
fi
if findmnt -rn -t nfs,nfs4 | grep -q .; then
  echo 'NFS mount detected; refusing to disable gssproxy' >&2
  exit 1
fi
if lsmod | awk '{print $1}' | grep -qx ipr; then
  echo 'ipr kernel module detected; refusing to disable ipr services' >&2
  exit 1
fi
systemctl disable --now \
  atd.service gssproxy.service iprdump.service iprinit.service \
  iprupdate.service oddjobd.service
systemctl is-active nginx mariadb postgresql ai-quant-api ai-quant-worker \
  crossborder-trend enterprise-ai-cockpit
echo 'Unused services disabled after dependency checks.'
""",
                root=True,
                timeout=60,
            )
        )
    finally:
        remote.close()


if __name__ == "__main__":
    main()
