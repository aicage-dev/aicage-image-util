#!/usr/bin/env bats

load "common.bash"

gpg_socket="$socket_directory/S.gpg-agent"

@test "GnuPG socket is ready from another container" {
  local volume sidecar
  new_volume_name volume
  new_sidecar_name sidecar
  docker volume create "$volume" >/dev/null
  docker run -d --name "$sidecar" --entrypoint /bin/sh -e GNUPGHOME=/tmp/gnupg \
    --mount "type=volume,src=$volume,dst=$socket_directory" "$image_ref" \
    -c 'mkdir -p /tmp/gnupg && chmod 700 /tmp/gnupg && exec credential-agent gpg serve' >/dev/null

  wait_for_socket "$sidecar" "$volume" gpg
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "GnuPG load defers wrong-passphrase failure until signing" {
  local volume sidecar credential_dir fingerprint
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  create_protected_gpg_fixture "$credential_dir" fingerprint
  start_gpg_sidecar "$volume" "$sidecar" "$credential_dir"
  printf '%s\n' wrong-passphrase \
    | docker exec -i --user "$host_user" "$sidecar" credential-agent gpg load "$fingerprint"
  if docker exec --user "$host_user" "$sidecar" gpg --batch --homedir /tmp/credential-agent \
    --local-user "$fingerprint!" --detach-sign --output /tmp/signature /dev/null; then
    return 1
  fi
  printf '%s\n' test-passphrase \
    | docker exec -i --user "$host_user" "$sidecar" credential-agent gpg load "$fingerprint"
  docker exec --user "$host_user" "$sidecar" gpg --batch --homedir /tmp/credential-agent \
    --local-user "$fingerprint!" --detach-sign --output /tmp/signature /dev/null
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "GnuPG load rejects a missing passphrase" {
  local volume sidecar credential_dir fingerprint
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir

  create_protected_gpg_fixture "$credential_dir" fingerprint
  start_gpg_sidecar "$volume" "$sidecar" "$credential_dir"
  if timeout 5 docker exec -i --user "$host_user" "$sidecar" \
    credential-agent gpg load "$fingerprint" </dev/null; then
    return 1
  fi
  assert_socket_volume_contains_only_sockets "$volume"
}

@test "GnuPG clients sign with protected and unprotected keys" {
  gpg_client_signs ""
  gpg_client_signs test-passphrase
}

gpg_client_signs() {
  local passphrase="$1"
  local volume sidecar credential_dir target_dir verify_dir result_dir fingerprint
  new_volume_name volume
  new_sidecar_name sidecar
  new_test_directory credential_dir
  new_test_directory target_dir
  new_test_directory verify_dir
  new_test_directory result_dir

  if [[ -n "$passphrase" ]]; then
    printf '%s\n' "$passphrase" | docker run --rm -i --user "$host_user" --entrypoint /bin/sh \
      -e GNUPGHOME=/credential/gnupg \
      --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
      'mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME" && gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key credential-agent-client@example.invalid ed25519 sign never'
  else
    docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
      --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
      'mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME" && gpg --batch --passphrase "" --quick-generate-key credential-agent-client@example.invalid ed25519 sign never'
  fi
  fingerprint="$(docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg" "$image_ref" -c \
    "gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print \$10; exit}'")"
  docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/credential/gnupg \
    --mount "type=bind,src=$credential_dir,dst=/credential/gnupg,readonly" \
    --mount "type=bind,src=$target_dir,dst=/target" "$image_ref" -c \
    "gpg --batch --armor --export '$fingerprint' > /target/public.asc"
  docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/target \
    --mount "type=bind,src=$target_dir,dst=/target" "$image_ref" -c \
    'chmod 700 "$GNUPGHOME" && gpg --batch --import /target/public.asc'
  docker run --rm --user "$host_user" --entrypoint /bin/sh -e GNUPGHOME=/verify \
    --mount "type=bind,src=$target_dir,dst=/target,readonly" \
    --mount "type=bind,src=$verify_dir,dst=/verify" "$image_ref" -c \
    'chmod 700 "$GNUPGHOME" && gpg --batch --import /target/public.asc'
  rm -f "$target_dir/S.gpg-agent"
  ln -s "$gpg_socket" "$target_dir/S.gpg-agent"

  start_gpg_sidecar "$volume" "$sidecar" "$credential_dir"
  if [[ -n "$passphrase" ]]; then
    printf '%s\n' "$passphrase" \
      | docker exec -i --user "$host_user" "$sidecar" credential-agent gpg load "$fingerprint"
  fi
  docker run --rm --user "$host_user" -e GNUPGHOME=/target \
    --mount "type=volume,src=$volume,dst=$socket_directory,readonly" \
    --mount "type=bind,src=$target_dir,dst=/target" \
    --mount "type=bind,src=$result_dir,dst=/result" \
    --entrypoint gpg "$image_ref" --batch --no-options --trust-model always --local-user "$fingerprint!" \
    --detach-sign --output /result/signature /dev/null
  docker run --rm --user "$host_user" -e GNUPGHOME=/verify \
    --mount "type=bind,src=$verify_dir,dst=/verify" \
    --mount "type=bind,src=$result_dir,dst=/result,readonly" \
    --entrypoint gpg "$image_ref" --batch --verify /result/signature /dev/null
  assert_gpg_client_homes_have_no_secret_key_or_passphrase_artifacts \
    "$passphrase" "$target_dir" "$verify_dir"
  assert_socket_volume_contains_only_sockets "$volume"
}
