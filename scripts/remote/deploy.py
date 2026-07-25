from __future__ import annotations

import argparse
import configparser
import json
import secrets
import subprocess
import sys
import tarfile
from datetime import UTC, datetime
from pathlib import Path

BLOG_ROOT = Path(__file__).resolve().parents[2]
CODES_ROOT = BLOG_ROOT.parent
QUANT_ROOT = CODES_ROOT / "ai-quantum"
CROSS_ROOT = CODES_ROOT / "crossborder-trend-report"
COCKPIT_ROOT = CODES_ROOT / "ai-agent-rag-demo"

sys.path.insert(0, str(QUANT_ROOT / "scripts" / "remote"))
from remote_client import RemoteClient  # noqa: E402


def read_ini(path: Path) -> configparser.ConfigParser:
    parser = configparser.ConfigParser(interpolation=None)
    if not parser.read(path, encoding="utf-8"):
        raise RuntimeError(f"Missing credentials file: {path}")
    return parser


def commit_id(root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], cwd=root, text=True
        ).strip()
    except subprocess.CalledProcessError:
        return "working"


def load_or_create_json(path: Path, factory) -> dict[str, str]:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    value = factory()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")
    return value


def prepare_secrets() -> tuple[dict[str, str], dict[str, str]]:
    blog_admin_path = BLOG_ROOT / ".deploy" / "blog-admin.json"
    quant_admin_path = QUANT_ROOT / ".deploy" / "blog-admin.json"
    source = quant_admin_path if quant_admin_path.exists() else blog_admin_path
    admin = load_or_create_json(
        source, lambda: {"token": secrets.token_urlsafe(32)}
    )
    for path in (blog_admin_path, quant_admin_path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(admin, indent=2), encoding="utf-8")

    cross = load_or_create_json(
        BLOG_ROOT / ".deploy" / "crossborder-secrets.json",
        lambda: {
            "jwtSecret": secrets.token_urlsafe(48),
            "adminPassword": secrets.token_urlsafe(16),
        },
    )
    return admin, cross


def systemd_env(values: dict[str, str]) -> bytes:
    lines = []
    for key, value in values.items():
        encoded = json.dumps(str(value), ensure_ascii=False)
        lines.append(f"{key}={encoded}")
    return ("\n".join(lines) + "\n").encode()


def build_archive(
    destination: Path, *, dist: Path, jar: Path | None = None
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(destination, "w:gz") as bundle:
        for source in sorted(dist.rglob("*")):
            if source.is_file():
                bundle.add(source, arcname=(Path("dist") / source.relative_to(dist)).as_posix())
        if jar is not None:
            bundle.add(jar, arcname="app.jar")


def find_jar(root: Path) -> Path:
    candidates = [
        item
        for item in (root / "backend" / "target").glob("*.jar")
        if not item.name.endswith(".jar.original")
    ]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one executable JAR in {root / 'backend/target'}")
    return candidates[0]


def render_service(template: Path, app_user: str = "aiapps") -> bytes:
    return template.read_text(encoding="utf-8").replace("__APP_USER__", app_user).encode()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    _, cross_secrets = prepare_secrets()
    if args.prepare_only:
        print("Local deployment secrets are ready in ignored .deploy directories.")
        return

    cross_credentials = read_ini(CROSS_ROOT / "credentials.txt")
    cockpit_credentials = read_ini(COCKPIT_ROOT / "credentials.txt")
    cross_mysql = cross_credentials["mysql.remote"]
    cross_llm = cross_credentials["deepseek.api"]
    cockpit_mysql = cockpit_credentials["mysql.remote"]
    cockpit_vector = cockpit_credentials["postgresql.vector"]
    cockpit_llm = cockpit_credentials["deepseek.api"]

    stamp = datetime.now(UTC).strftime("%Y%m%d%H%M%S")
    releases = {
        "blog": f"{stamp}-{commit_id(BLOG_ROOT)}",
        "cross": f"{stamp}-{commit_id(CROSS_ROOT)}",
        "cockpit": f"{stamp}-{commit_id(COCKPIT_ROOT)}",
    }
    state = BLOG_ROOT / ".deploy"
    archives = {
        "blog": state / f"blog-{releases['blog']}.tar.gz",
        "cross": state / f"cross-{releases['cross']}.tar.gz",
        "cockpit": state / f"cockpit-{releases['cockpit']}.tar.gz",
    }
    build_archive(archives["blog"], dist=BLOG_ROOT / "dist")
    build_archive(
        archives["cross"],
        dist=CROSS_ROOT / "frontend" / "dist",
        jar=find_jar(CROSS_ROOT),
    )
    build_archive(
        archives["cockpit"],
        dist=COCKPIT_ROOT / "frontend" / "dist",
        jar=find_jar(COCKPIT_ROOT),
    )

    cross_env = systemd_env(
        {
            "SERVER_ADDRESS": "127.0.0.1",
            "SERVER_PORT": "8090",
            "MYSQL_HOST": "127.0.0.1",
            "MYSQL_PORT": cross_mysql.get("port", "3306"),
            "MYSQL_DATABASE": cross_mysql["database"],
            "MYSQL_USER": cross_mysql["user"],
            "MYSQL_PASSWORD": cross_mysql["password"],
            "DB_POOL_MAX_SIZE": "3",
            "DB_POOL_MIN_IDLE": "0",
            "TOMCAT_MAX_THREADS": "20",
            "TOMCAT_MIN_SPARE_THREADS": "2",
            "TOMCAT_MAX_CONNECTIONS": "40",
            "TOMCAT_ACCEPT_COUNT": "20",
            "AUTH_ENABLED": "true",
            "JWT_SECRET": cross_secrets["jwtSecret"],
            "INITIAL_ADMIN_PASSWORD": cross_secrets["adminPassword"],
            "CORS_ALLOWED_ORIGINS": "https://101.132.78.217",
            "SOURCE_MODE": "external",
            "AI_ENRICHMENT_ENABLED": "true",
            "DEEPSEEK_BASE_URL": cross_llm.get("base-url", "https://api.deepseek.com"),
            "DEEPSEEK_API_KEY": cross_llm["api-key"],
            "DEEPSEEK_MODEL": cross_llm.get("model", "deepseek-v4-pro"),
        }
    )
    cockpit_env = systemd_env(
        {
            "SERVER_ADDRESS": "127.0.0.1",
            "SERVER_PORT": "8080",
            "APP_REPOSITORY_MODE": "mysql",
            "MYSQL_URL": (
                "jdbc:mysql://127.0.0.1:"
                f"{cockpit_mysql.get('port', '3306')}/{cockpit_mysql['database']}"
                "?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai"
                "&useSSL=false&allowPublicKeyRetrieval=true"
            ),
            "MYSQL_USER": cockpit_mysql["user"],
            "MYSQL_PASSWORD": cockpit_mysql["password"],
            "DB_POOL_MAX_SIZE": "2",
            "DB_POOL_MIN_IDLE": "0",
            "QUARTZ_THREAD_COUNT": "2",
            "FLYWAY_ENABLED": "true",
            "FLYWAY_BASELINE_ON_MIGRATE": "true",
            "FLYWAY_BASELINE_VERSION": "0",
            "LLM_ENABLED": "true",
            "LLM_PROVIDER": "spring-ai",
            "OPENAI_BASE_URL": cockpit_llm.get(
                "base-url", "https://api.deepseek.com"
            ),
            "OPENAI_API_KEY": cockpit_llm["api-key"],
            "DEEPSEEK_API_KEY": cockpit_llm["api-key"],
            "LLM_MODEL": cockpit_llm.get("model", "deepseek-v4-flash"),
            "VECTOR_ENABLED": "true",
            "VECTOR_DATABASE_URL": (
                "jdbc:postgresql://127.0.0.1:"
                f"{cockpit_vector.get('port', '5432')}/{cockpit_vector['database']}"
            ),
            "VECTOR_DATABASE_USER": cockpit_vector["user"],
            "VECTOR_DATABASE_PASSWORD": cockpit_vector["password"],
            "VECTOR_DATABASE_SCHEMA": "public",
            "EMBEDDING_MODE": "local",
            "EMBEDDING_DIMENSIONS": cockpit_credentials.get(
                "embedding", "dimensions", fallback="1536"
            ),
            "MCP_ENABLED": "false",
        }
    )

    remote = RemoteClient()
    remote_paths = {
        key: f"/tmp/{path.name}" for key, path in archives.items()
    }
    try:
        for key, path in archives.items():
            remote.upload_file(path, remote_paths[key], 0o600)
        remote.upload_bytes(cross_env, "/tmp/crossborder-app.env", 0o600)
        remote.upload_bytes(cockpit_env, "/tmp/cockpit-app.env", 0o600)
        remote.upload_bytes(
            render_service(
                CROSS_ROOT
                / "deploy"
                / "systemd"
                / "crossborder-trend.service.template"
            ),
            "/tmp/crossborder-trend.service",
            0o644,
        )
        remote.upload_bytes(
            render_service(
                COCKPIT_ROOT
                / "deploy"
                / "systemd"
                / "enterprise-ai-cockpit.service.template"
            ),
            "/tmp/enterprise-ai-cockpit.service",
            0o644,
        )
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
            BLOG_ROOT / "deploy" / "sample-resources.sh",
            "/tmp/ai-platform-sample-resources",
            0o755,
        )

        wrapper = f"""#!/usr/bin/env bash
set -euo pipefail
dnf -y --disablerepo='epel*' install java-17-openjdk-headless nginx >/dev/null
java17="$(find /usr/lib/jvm -type f -path '*java-17*/bin/java' | head -n 1)"
test -x "$java17"
ln -sfn "$java17" /usr/local/bin/java17
id aiapps >/dev/null 2>&1 || useradd --system --home-dir /opt/ai-platform --shell /sbin/nologin aiapps

install_release() {{
  local root="$1" release="$2" archive="$3" web_path="$4"
  mkdir -p "$root/releases/$release" "$root/shared" "$root/www"
  tar -xzf "$archive" -C "$root/releases/$release"
  chown -R aiapps:aiapps "$root/releases/$release" "$root/shared"
  ln -sfn "$root/releases/$release" "$root/current.next"
  mv -Tf "$root/current.next" "$root/current"
  ln -sfn "$root/releases/$release/dist" "$root/www/$web_path.next"
  mv -Tf "$root/www/$web_path.next" "$root/www/$web_path"
  chmod 755 "$root" "$root/releases" "$root/www" "$root/releases/$release"
}}

install_release /opt/ai-blog {releases['blog']} {remote_paths['blog']} blog
install_release /opt/crossborder-trend-report {releases['cross']} {remote_paths['cross']} crossBorderTrend
install_release /opt/enterprise-ai-cockpit {releases['cockpit']} {remote_paths['cockpit']} smartCockpit
install -o aiapps -g aiapps -m 600 /tmp/crossborder-app.env /opt/crossborder-trend-report/shared/app.env
install -o aiapps -g aiapps -m 600 /tmp/cockpit-app.env /opt/enterprise-ai-cockpit/shared/app.env
install -m 644 /tmp/crossborder-trend.service /etc/systemd/system/crossborder-trend.service
install -m 644 /tmp/enterprise-ai-cockpit.service /etc/systemd/system/enterprise-ai-cockpit.service
install -m 644 /tmp/ai-platform-nginx.conf /etc/nginx/nginx.conf
install -m 644 /tmp/ai-platform.conf /etc/nginx/conf.d/ai-platform.conf
rm -f /etc/nginx/conf.d/ai-quant.conf
install -m 755 /tmp/ai-platform-sample-resources /usr/local/sbin/ai-platform-sample-resources

systemctl daemon-reload
systemctl enable crossborder-trend.service enterprise-ai-cockpit.service >/dev/null
systemctl restart crossborder-trend.service enterprise-ai-cockpit.service

wait_for() {{
  local url="$1"
  for _attempt in $(seq 1 60); do
    curl -fsS "$url" >/dev/null && return 0
    sleep 2
  done
  return 1
}}
wait_for http://127.0.0.1:8090/api/health
wait_for http://127.0.0.1:8080/api/health

nginx -t
systemctl restart nginx
systemctl is-active --quiet nginx ai-quant-api crossborder-trend enterprise-ai-cockpit

for root in /opt/ai-blog /opt/crossborder-trend-report /opt/enterprise-ai-cockpit; do
  find "$root/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\\n' \\
    | sort -nr | tail -n +6 | cut -d' ' -f2- | xargs -r rm -rf
done

rm -f {' '.join(remote_paths.values())} /tmp/crossborder-app.env /tmp/cockpit-app.env
systemd-run --unit=ai-platform-resource-sample --collect \\
  /usr/local/sbin/ai-platform-sample-resources >/dev/null
"""
        remote.upload_bytes(wrapper.encode(), "/tmp/deploy-ai-platform.sh", 0o700)
        output = remote.run(
            "/bin/bash /tmp/deploy-ai-platform.sh", root=True, timeout=900
        )
        print(output)
    finally:
        remote.close()
        for archive in archives.values():
            archive.unlink(missing_ok=True)

    print("PUBLIC_URL=https://101.132.78.217/")
    print(f"BLOG_RELEASE={releases['blog']}")
    print(f"CROSS_RELEASE={releases['cross']}")
    print(f"COCKPIT_RELEASE={releases['cockpit']}")


if __name__ == "__main__":
    main()
