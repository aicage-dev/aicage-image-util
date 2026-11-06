#!/usr/bin/env bash
set -euo pipefail

image_ref="$1"
host_user="$(id -u):$(id -g)"
sidecars=()
volumes=()
directories=()

cleanup() {
  local path sidecar volume
  for sidecar in "${sidecars[@]}"; do
    docker rm -f "$sidecar" >/dev/null 2>&1 || true
  done
  for volume in "${volumes[@]}"; do
    docker volume rm "$volume" >/dev/null 2>&1 || true
  done
  for path in "${directories[@]}"; do
    rm -rf "$path"
  done
}

trap cleanup EXIT

test_socket() {
  local protocol="$1"
  local volume="aicage-credential-test-${RANDOM}-${RANDOM}"
  local sidecar="aicage-credential-test-${RANDOM}-${RANDOM}"
  sidecars+=("$sidecar")
  volumes+=("$volume")
  docker volume create "$volume" >/dev/null
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

test_ssh_load() {
  local volume="aicage-credential-test-${RANDOM}-${RANDOM}"
  local sidecar="aicage-credential-test-${RANDOM}-${RANDOM}"
  local credential_dir
  credential_dir="$(mktemp -d "$PWD/.credential-agent-test.XXXXXX")"
  sidecars+=("$sidecar")
  volumes+=("$volume")
  directories+=("$credential_dir")

  ssh-keygen -q -t ed25519 -N test-passphrase -f "$credential_dir/id_ed25519"
  docker volume create "$volume" >/dev/null
  _prepare_socket_volume "$volume"
  docker run -d --user "$host_user" --name "$sidecar" \
    --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" \
    --mount "type=bind,src=$credential_dir,dst=/credential/ssh,readonly" \
    "$image_ref" ssh serve >/dev/null

  for _ in $(seq 1 20); do
    docker exec "$sidecar" aicage-credential-agent ssh ready && break
    sleep 1
  done
  printf '%s\n' test-passphrase \
    | docker exec -i "$sidecar" aicage-credential-agent ssh load /credential/ssh/id_ed25519
  docker run --rm -e SSH_AUTH_SOCK=/run/aicage-credential-agent/ssh-agent.sock \
    --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" \
    --entrypoint ssh-add "$image_ref" -l | grep -q ED25519
  _assert_socket_volume_has_no_files "$volume"
}

test_gpg_load() {
  local volume="aicage-credential-test-${RANDOM}-${RANDOM}"
  local sidecar="aicage-credential-test-${RANDOM}-${RANDOM}"
  local credential_dir fingerprint
  credential_dir="$(mktemp -d "$PWD/.credential-agent-test.XXXXXX")"
  sidecars+=("$sidecar")
  volumes+=("$volume")
  directories+=("$credential_dir")

  docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
    'mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME" && printf "%s\\n" test-passphrase | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key credential-agent-test@example.invalid default default never'
  fingerprint="$(docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
    "gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print \$10; exit}'")"

  docker volume create "$volume" >/dev/null
  _prepare_socket_volume "$volume"
  docker run -d --user "$host_user" --name "$sidecar" -e GNUPGHOME=/credential/gnupg \
    --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg,readonly" \
    "$image_ref" gpg serve >/dev/null
  for _ in $(seq 1 20); do
    docker exec "$sidecar" aicage-credential-agent gpg ready && break
    sleep 1
  done
  printf '%s\n' test-passphrase \
    | docker exec -i --user "$host_user" "$sidecar" aicage-credential-agent gpg load "$fingerprint"
  docker exec --user "$host_user" "$sidecar" gpg --batch --homedir /tmp/aicage-credential-agent \
    --local-user "$fingerprint!" --detach-sign --output /tmp/signature /dev/null
  _assert_socket_volume_has_no_files "$volume"
}

_assert_socket_volume_has_no_files() {
  local volume="$1"
  docker run --rm --entrypoint /bin/sh \
    --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" "$image_ref" -c \
    '! find /run/aicage-credential-agent -type f -print -quit | grep -q .'
}

_prepare_socket_volume() {
  local volume="$1"
  docker run --rm --entrypoint /bin/sh \
    --mount "type=volume,src=$volume,dst=/run/aicage-credential-agent" "$image_ref" -c \
    "chown $host_user /run/aicage-credential-agent"
}

test_socket ssh
test_socket gpg
test_ssh_load
test_gpg_load
