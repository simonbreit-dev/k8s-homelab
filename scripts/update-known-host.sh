#!/usr/bin/env bash
set -euo pipefail

host="$1"
known_hosts="${HOME}/.ssh/known_hosts_k8s_lab"

mkdir -p "$(dirname "$known_hosts")"
touch "$known_hosts"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Waiting for SSH on ${host}..."

for attempt in {1..30}; do
  if ssh-keyscan \
      -T 3 \
      -H \
      -t ed25519 \
      "$host" \
      >"$tmp" 2>/dev/null &&
     [[ -s "$tmp" ]]; then

    echo "SSH host key found for ${host}"

    # Erst jetzt alten Key entfernen
    ssh-keygen \
      -R "$host" \
      -f "$known_hosts" \
      >/dev/null 2>&1 || true

    cat "$tmp" >>"$known_hosts"

    exit 0
  fi

  echo "Waiting for ${host} (${attempt}/60)..."
  sleep 2
done

echo "Timed out waiting for SSH on ${host}" >&2
exit 1