#!/usr/bin/env bash
set -euo pipefail

image_ref="$1"

test_socket() {
  local protocol="$1"
  local volume="aicage-credential-test-${RANDOM}-${RANDOM}"
  local sidecar="aicage-credential-test-${RANDOM}-${RANDOM}"
  docker volume create "$volume" >/dev/null
  trap 'docker rm -f "$sidecar" >/dev/null 2>&1 || true; docker volume rm "$volume" >/dev/null 2>&1 || true' RETURN
  if [[ "$protocol" == gpg ]]; then
    docker run -d --name "$sidecar" --entrypoint /bin/sh -e GNUPGHOME=/tmp/gnupg \
      --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" "$image_ref" \
      -c 'mkdir -p /tmp/gnupg && chmod 700 /tmp/gnupg && exec aicage-credential-agent gpg serve' >/dev/null
  else
    docker run -d --name "$sidecar" --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" \
      "$image_ref" ssh serve >/dev/null
  fi
  for _ in $(seq 1 20); do
    docker run --rm --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" \
      "$image_ref" "$protocol" ready && return
    sleep 1
  done
  docker logs "$sidecar"
  return 1
}

test_socket ssh
test_socket gpg
