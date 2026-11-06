#!/usr/bin/env bats

load "common.bash"

@test "dispatcher rejects invalid commands" {
  run docker run --rm "$image_ref"
  [ "$status" -ne 0 ]

  run docker run --rm "$image_ref" ssh invalid
  [ "$status" -ne 0 ]

  run docker run --rm "$image_ref" gpg invalid
  [ "$status" -ne 0 ]
}
