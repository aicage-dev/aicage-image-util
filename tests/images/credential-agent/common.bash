image_ref="${AICAGE_IMAGE_UTIL_TEST_IMAGE:?Set AICAGE_IMAGE_UTIL_TEST_IMAGE}"
test_root="$(git rev-parse --show-toplevel)/.credential-agent-test"
host_user="$(id -u):$(id -g)"
socket_directory="/run/aicage-credential-agent"
ssh_socket="$socket_directory/ssh-agent.sock"

setup() {
  sidecars=()
  volumes=()
  directories=()
  mkdir -p "$test_root"
}

teardown() {
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

new_test_directory() {
  local variable_name="$1"
  local directory
  directory="$(mktemp -d "$test_root/XXXXXX")"
  directories+=("$directory")
  printf -v "$variable_name" '%s' "$directory"
}

new_sidecar_name() {
  local variable_name="$1"
  local name="aicage-credential-agent-test-sidecar-$BATS_TEST_NUMBER-$RANDOM"
  sidecars+=("$name")
  printf -v "$variable_name" '%s' "$name"
}

new_volume_name() {
  local variable_name="$1"
  local name="aicage-credential-agent-test-volume-$BATS_TEST_NUMBER-$RANDOM"
  volumes+=("$name")
  printf -v "$variable_name" '%s' "$name"
}

assert_socket_volume_contains_only_sockets() {
  local volume="$1"
  docker run --rm --entrypoint /bin/sh \
    --mount "type=volume,src=$volume,dst=$socket_directory" "$image_ref" -c \
    "! find $socket_directory -mindepth 1 ! -type s -print -quit | grep -q ."
}

wait_for_socket() {
  local sidecar="$1"
  local volume="$2"
  local protocol="$3"
  for _ in $(seq 1 20); do
    if docker run --rm --mount "type=volume,src=$volume,dst=$socket_directory" \
      "$image_ref" "$protocol" ready; then
      return
    fi
    sleep 1
  done
  docker logs "$sidecar"
  return 1
}

prepare_socket_volume() {
  local volume="$1"
  docker run --rm --entrypoint /bin/sh \
    --mount "type=volume,src=$volume,dst=$socket_directory" "$image_ref" -c \
    "chown $host_user $socket_directory"
}

create_protected_gpg_fixture() {
  local credential_dir="$1"
  local fingerprint_variable="$2"
  docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
    'mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME" && printf "%s\\n" test-passphrase | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key credential-agent-test@example.invalid default default never'
  local fixture_fingerprint
  fixture_fingerprint="$(docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
    "gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print \$10; exit}'")"
  printf -v "$fingerprint_variable" '%s' "$fixture_fingerprint"
}

start_gpg_sidecar() {
  local volume="$1"
  local sidecar="$2"
  local credential_dir="$3"
  docker volume create "$volume" >/dev/null
  prepare_socket_volume "$volume"
  docker run -d --user "$host_user" --name "$sidecar" -e GNUPGHOME=/credential/gnupg \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg,readonly" \
    "$image_ref" gpg serve >/dev/null
  wait_for_socket "$sidecar" "$volume" gpg
}

start_ssh_sidecar() {
  local volume="$1"
  local sidecar="$2"
  local credential_dir="$3"
  docker volume create "$volume" >/dev/null
  prepare_socket_volume "$volume"
  run_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
}

run_ssh_sidecar() {
  local volume="$1"
  local sidecar="$2"
  local credential_dir="$3"
  docker run -d --user "$host_user" --name "$sidecar" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --mount "type=bind,src=$credential_dir,dst=/credential/ssh,readonly" \
    "$image_ref" ssh serve >/dev/null
  wait_for_socket "$sidecar" "$volume" ssh
}

authenticate_with_ssh_agent() {
  local sshd="$1"
  local volume="$2"
  for _ in $(seq 1 20); do
    if docker run --rm --network "container:$sshd" \
      -e "SSH_AUTH_SOCK=$ssh_socket" \
      --mount "type=volume,src=$volume,dst=$socket_directory,readonly" \
      --entrypoint ssh "$image_ref" -p 2222 -o BatchMode=yes -o PasswordAuthentication=no \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1 true; then
      return
    fi
    sleep 1
  done
  docker logs "$sshd"
  return 1
}

assert_gpg_client_homes_have_no_secret_key_or_passphrase_artifacts() {
  local passphrase="$1"
  shift
  local client_home
  for client_home in "$@"; do
    test ! -d "$client_home/private-keys-v1.d" \
      || test -z "$(find "$client_home/private-keys-v1.d" -type f -print -quit)"
    test ! -e "$client_home/secring.gpg"
    if [[ -n "$passphrase" ]] && find "$client_home" -type f -exec grep -aF -l -- "$passphrase" {} + | grep -q .; then
      return 1
    fi
    if docker run --rm --user "$host_user" -e GNUPGHOME=/client \
      --mount "type=bind,src=$client_home,dst=/client,readonly" \
      --entrypoint gpg "$image_ref" --batch --with-colons --list-secret-keys \
      | grep -qE '^(sec|ssb):'; then
      return 1
    fi
  done
}
