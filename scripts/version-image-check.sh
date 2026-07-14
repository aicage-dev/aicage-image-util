#!/usr/bin/env bash
set -euo pipefail

AGENTS_DIR="${1:-agents}"
VERSION_CHECK_IMAGE="${2:-ghcr.io/aicage/aicage-image-util:agent-version}"
had_errors=0

get_image_version() {
  local version_script="$1"
  local script_name
  local script_path
  script_name="$(basename "${version_script}")"
  script_path="$(cd "$(dirname "${version_script}")" && pwd)/${script_name}"
  docker run --rm \
    -v "${script_path}:/tmp/${script_name}:ro" \
    "${VERSION_CHECK_IMAGE}" \
    "/tmp/${script_name}" \
    2>/dev/null
}

printf "%-20s %-20s %-24s %-10s\n" "Agent" "Host Version" "Util Image Version" "Mismatch"
printf "%-20s %-20s %-24s %-10s\n" "-----" "------------" "------------------" "--------"

for agent_dir in "${AGENTS_DIR}"/*; do
  agent="$(basename "${agent_dir}")"
  version_script="${agent_dir}/version.sh"
  host_version="$(bash "${version_script}")"
  image_version="$(get_image_version "${version_script}")"

  mismatch="no"
  if [[ "${host_version}" != "${image_version}" || -z "${image_version}" ]]; then
    mismatch="yes"
    echo "error: ${agent} has version mismatch or empty version" >&2
    had_errors=1
  fi

  printf "%-20s %-20s %-24s %-10s\n" "${agent}" "${host_version}" \
    "${image_version}" "${mismatch}"
done

if [[ "${had_errors}" -ne 0 ]]; then
  exit 1
fi
