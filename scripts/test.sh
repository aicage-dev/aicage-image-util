#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_ref=""
variant=""

usage() {
  echo "Usage: scripts/test.sh --variant agent-version --image <image-ref> [-- <bats-args>]" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      [[ $# -ge 2 ]] || usage
      variant="${2:-}"
      shift 2
      ;;
    --image)
      [[ $# -ge 2 ]] || usage
      image_ref="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$image_ref" && -n "$variant" ]] || usage
[[ -d "$root_dir/tests/images/$variant" ]] || usage

export AICAGE_IMAGE_UTIL_TEST_IMAGE="$image_ref"
exec bats "$root_dir/tests/images/$variant" "$@"
