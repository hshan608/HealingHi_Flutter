#!/usr/bin/env bash
# For a separate, always-on Linux host; invoke with bash, not sh.
set -euo pipefail
config_file="${KEEPALIVE_ENV_FILE:-/etc/healinghi/keepalive.env}"
if [[ ! -r "$config_file" ]]; then
  echo 'Keep-alive environment file is missing or unreadable.' >&2
  exit 1
fi
set -a
source "$config_file"
set +a
: "${KEEPALIVE_HEARTBEAT_URL:?Configure a separate heartbeat for the backup scheduler}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/../scripts/supabase_healthcheck.py" run
