#!/usr/bin/env bash
set -euo pipefail

STATUS_FILE=/opt/ai-blog/current/dist/runtime-status.json

sample_window() {
  local breached=0
  local previous_total previous_idle
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  previous_idle=$((idle + iowait))
  previous_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

  for _sample in $(seq 1 30); do
    sleep 10
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    current_idle=$((idle + iowait))
    current_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    total_delta=$((current_total - previous_total))
    idle_delta=$((current_idle - previous_idle))
    cpu=$((total_delta > 0 ? (100 * (total_delta - idle_delta) / total_delta) : 0))
    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    memory=$((100 * (mem_total - mem_available) / mem_total))
    if ((cpu > 80 || memory > 80 || (cpu > 70 && memory > 70))); then
      breached=1
    fi
    previous_idle=$current_idle
    previous_total=$current_total
  done
  return "$breached"
}

cockpit_status=running
crossborder_status=running

if ! sample_window; then
  systemctl disable --now enterprise-ai-cockpit.service
  cockpit_status=paused
  if ! sample_window; then
    systemctl disable --now crossborder-trend.service
    crossborder_status=paused
  fi
fi

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$STATUS_FILE" <<EOF
{
  "generatedAt": "$timestamp",
  "projects": {
    "quant": { "state": "live" },
    "crossborder": { "state": "$([[ "$crossborder_status" == "running" ]] && echo live || echo paused)" },
    "cockpit": { "state": "$([[ "$cockpit_status" == "running" ]] && echo live || echo paused)" }
  }
}
EOF
chmod 644 "$STATUS_FILE"
