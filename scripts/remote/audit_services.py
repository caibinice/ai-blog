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
echo AT_QUEUE
atq 2>/dev/null || true
echo CANDIDATES
for service in atd gssproxy iprdump iprinit iprupdate oddjobd; do
  if systemctl list-unit-files "$service.service" --no-legend 2>/dev/null | grep -q .; then
    active=$(systemctl is-active "$service.service" 2>/dev/null || true)
    enabled=$(systemctl is-enabled "$service.service" 2>/dev/null || true)
    reverse=$(systemctl list-dependencies --reverse "$service.service" --plain \
      --no-legend 2>/dev/null | grep -v "$service.service" | sed '/^$/d' \
      | tr '\\n' ',' | sed 's/,$//')
    echo "$service active=$active enabled=$enabled reverse_dependencies=${reverse:-none}"
  fi
done
""",
                root=True,
                timeout=60,
            )
        )
    finally:
        remote.close()


if __name__ == "__main__":
    main()
