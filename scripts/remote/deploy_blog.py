from __future__ import annotations

import subprocess
import sys
import tarfile
from datetime import UTC, datetime
from pathlib import Path

BLOG_ROOT = Path(__file__).resolve().parents[2]
QUANT_ROOT = BLOG_ROOT.parent / "ai-quantum"
sys.path.insert(0, str(QUANT_ROOT / "scripts" / "remote"))
from remote_client import RemoteClient  # noqa: E402


def main() -> None:
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=BLOG_ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        commit = "working"
    release = datetime.now(UTC).strftime("%Y%m%d%H%M%S") + f"-{commit}"
    archive = BLOG_ROOT / ".deploy" / f"blog-{release}.tar.gz"
    archive.parent.mkdir(exist_ok=True)
    with tarfile.open(archive, "w:gz") as bundle:
        for source in sorted((BLOG_ROOT / "dist").rglob("*")):
            if source.is_file():
                bundle.add(
                    source,
                    arcname=(Path("dist") / source.relative_to(BLOG_ROOT / "dist")).as_posix(),
                )

    remote = RemoteClient()
    remote_archive = f"/tmp/{archive.name}"
    try:
        remote.upload_file(archive, remote_archive, 0o600)
        print(
            remote.run(
                f"""
set -euo pipefail
root=/opt/ai-blog
target="$root/releases/{release}"
mkdir -p "$target"
tar -xzf {remote_archive} -C "$target"
chown -R aiapps:aiapps "$target"
chmod 755 "$target"
ln -sfn "$target" "$root/current.next"
mv -Tf "$root/current.next" "$root/current"
nginx -t
systemctl reload nginx
find "$root/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\\n' \
  | sort -nr | tail -n +6 | cut -d' ' -f2- | xargs -r rm -rf
rm -f {remote_archive}
curl -fsS https://127.0.0.1/ -k -H 'Host: 101.132.78.217' >/dev/null
echo 'Blog release activated: {release}'
""",
                root=True,
                timeout=120,
            )
        )
    finally:
        remote.close()
        archive.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
