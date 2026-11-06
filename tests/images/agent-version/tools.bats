#!/usr/bin/env bats

image_ref="${AICAGE_IMAGE_UTIL_TEST_IMAGE:?Set AICAGE_IMAGE_UTIL_TEST_IMAGE}"

@test "includes Bash" {
  run docker run --rm "$image_ref" sh -c 'bash --version'

  [ "$status" -eq 0 ]
}

@test "includes Node and npm" {
  run docker run --rm "$image_ref" sh -c 'node --version && npm --version'

  [ "$status" -eq 0 ]
}

@test "includes Python and pip" {
  run docker run --rm "$image_ref" sh -c 'python3 --version && pip --version'

  [ "$status" -eq 0 ]
}

@test "includes curl" {
  run docker run --rm "$image_ref" sh -c 'curl --version'

  [ "$status" -eq 0 ]
}

@test "includes jq" {
  run docker run --rm "$image_ref" sh -c \
    "printf '%s\\n' '{\"version\":\"1.2.3\"}' | jq -er .version"

  [ "$status" -eq 0 ]
  [ "$output" = 1.2.3 ]
}
