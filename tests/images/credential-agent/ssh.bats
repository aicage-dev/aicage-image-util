#!/usr/bin/env bats

load "common.bash"

sshd_image="credential-agent-test-sshd"

setup_file() {
  docker build -t "$sshd_image" -f "$BATS_TEST_DIRNAME/sshd/Dockerfile" . >/dev/null
}

@test "SSH socket is ready from another container" {
  local volume sidecar
  new_volume_name volume
  new_sidecar_name sidecar
  docker volume create "$volume" >/dev/null
  docker run -d --name "$sidecar" --mount "type=volume,src=$volume,dst=$socket_directory" \
    "$image_ref" ssh serve >/dev/null

  wait_for_socket "$sidecar" "$volume" ssh
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "SSH list returns no output when the agent has no identities" {
  local volume sidecar
  new_volume_name volume
  new_sidecar_name sidecar
  docker volume create "$volume" >/dev/null
  docker run -d --name "$sidecar" --mount "type=volume,src=$volume,dst=$socket_directory" \
    "$image_ref" ssh serve >/dev/null

  wait_for_socket "$sidecar" "$volume" ssh
  run docker exec "$sidecar" credential-agent ssh list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "encrypted SSH key loads and authenticates" {
  local volume sidecar credential_dir public_dir message_dir sshd
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir
  new_test_directory public_dir
  new_test_directory message_dir

  ssh-keygen -q -t ed25519 -N test-passphrase -f "$credential_dir/id_ed25519"
  cp "$credential_dir/id_ed25519.pub" "$public_dir/id_ed25519.pub"
  cp "$credential_dir/id_ed25519.pub" "$public_dir/authorized_keys"
  printf 'aicage ' > "$public_dir/allowed_signers"
  cat "$credential_dir/id_ed25519.pub" >> "$public_dir/allowed_signers"
  printf 'credential-agent test message\n' > "$message_dir/message"
  start_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  printf '%s\n' test-passphrase \
    | docker exec -i "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519
  docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --entrypoint ssh-add "$image_ref" -l | grep -q ED25519
  docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory,readonly" \
    --mount "type=bind,src=$public_dir,dst=/public,readonly" \
    --mount "type=bind,src=$message_dir,dst=/message" \
    --entrypoint ssh-keygen "$image_ref" -Y sign -U -f /public/id_ed25519.pub -n aicage /message/message
  docker run --rm \
    --mount "type=bind,src=$public_dir,dst=/public,readonly" \
    --mount "type=bind,src=$message_dir,dst=/message,readonly" \
    --entrypoint /bin/sh "$image_ref" -c \
    'ssh-keygen -Y verify -f /public/allowed_signers -I aicage -n aicage -s /message/message.sig < /message/message'
  new_sidecar_name sshd
  docker run -d --name "$sshd" --mount "type=bind,src=$public_dir/authorized_keys,dst=/authorized_keys,readonly" \
    "$sshd_image" >/dev/null
  authenticate_with_ssh_agent "$sshd" "$volume"
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "unencrypted SSH key loads" {
  local volume sidecar credential_dir
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  ssh-keygen -q -t ed25519 -N '' -f "$credential_dir/id_ed25519"
  start_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519
  docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --entrypoint ssh-add "$image_ref" -l | grep -q ED25519
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "SSH list and remove reconcile one identity" {
  local volume sidecar credential_dir first_identity
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  ssh-keygen -q -t ed25519 -N '' -f "$credential_dir/id_ed25519_one"
  ssh-keygen -q -t ed25519 -N '' -f "$credential_dir/id_ed25519_two"
  start_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519_one
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519_two
  first_identity="$(cat "$credential_dir/id_ed25519_one.pub")"

  run docker exec "$sidecar" credential-agent ssh list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$first_identity"* ]]
  printf '%s\n' "$first_identity" | docker exec -i "$sidecar" credential-agent ssh remove

  run docker exec "$sidecar" credential-agent ssh list
  [ "$status" -eq 0 ]
  [[ "$output" != *"$first_identity"* ]]
  test "$(printf '%s\n' "$output" | wc -l)" -eq 1
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "SSH load accepts a permissive private key bind mount" {
  local volume sidecar credential_dir
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  ssh-keygen -q -t ed25519 -N '' -f "$credential_dir/id_ed25519"
  chmod 0777 "$credential_dir/id_ed25519"
  start_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519
  docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --entrypoint ssh-add "$image_ref" -l | grep -q ED25519
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "SSH load rejects missing and wrong passphrases" {
  local volume sidecar credential_dir
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  ssh-keygen -q -t ed25519 -N test-passphrase -f "$credential_dir/id_ed25519"
  start_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  if printf '%s\n' wrong-passphrase \
    | docker exec -i "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519; then
    return 1
  fi
  if timeout 5 docker exec -i "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519 </dev/null; then
    return 1
  fi
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "SSH sidecar recreation requires identity reload" {
  local volume sidecar credential_dir
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  ssh-keygen -q -t ed25519 -N '' -f "$credential_dir/id_ed25519_one"
  ssh-keygen -q -t ed25519 -N '' -f "$credential_dir/id_ed25519_two"
  start_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  docker run --rm --user "$host_user" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    "$image_ref" ssh ready
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519_one
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519_two
  test "$(docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --entrypoint ssh-add "$image_ref" -l | grep -c ED25519)" -eq 2

  docker rm -f "$sidecar" >/dev/null
  run_ssh_sidecar "$volume" "$sidecar" "$credential_dir"
  docker run --rm --user "$host_user" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    "$image_ref" ssh ready
  if docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --entrypoint ssh-add "$image_ref" -l; then
    return 1
  fi
  docker exec "$sidecar" credential-agent ssh load /credential/ssh/id_ed25519_one
  docker run --rm -e "SSH_AUTH_SOCK=$ssh_socket" \
    --mount "type=volume,src=$volume,dst=$socket_directory" \
    --entrypoint ssh-add "$image_ref" -l | grep -q ED25519
  assert_socket_volume_contains_only_sockets "$volume"
}
