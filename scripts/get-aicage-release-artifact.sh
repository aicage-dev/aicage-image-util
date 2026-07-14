#!/usr/bin/env bash
set -euo pipefail

# Prerequisites:
# - cosign
# - curl
# - tar

AICAGE_REPO="$1"
TARGET_DIR="$2"
ARTIFACT_NAME="${3:-${AICAGE_REPO}.tar.gz}"

mkdir -p "${TARGET_DIR}"
pushd "${TARGET_DIR}" >/dev/null

echo "Downloading release artifact from 'github.com/aicage/${AICAGE_REPO}' to ${TARGET_DIR} ..." >&2

for artifact in "${ARTIFACT_NAME}" SHA256SUMS SHA256SUMS.sigstore.json; do
  curl -fsSLO \
    --retry 8 \
    --retry-all-errors \
    --retry-delay 2 \
    --max-time 600 \
    "https://github.com/aicage/${AICAGE_REPO}/releases/latest/download/${artifact}"
done

echo "Verifying signature ..." >&2

cosign verify-blob \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --certificate-identity-regexp "^https://github\.com/aicage/${AICAGE_REPO}/\.github/workflows/release\.yml@(?:refs/tags/.*|[0-9a-f]{40})$" \
  SHA256SUMS \
  >&2

echo "Verifying checksums ..." >&2

grep "  \\./${ARTIFACT_NAME}$" SHA256SUMS | sha256sum -c - >&2

echo "Unpacking ..." >&2

tar -xzf "${ARTIFACT_NAME}" >&2

echo "Clean up ..." >&2

rm "${ARTIFACT_NAME}" SHA256SUMS SHA256SUMS.sigstore.json >&2

popd >/dev/null

echo "Done downloading release artifact from 'github.com/aicage/${AICAGE_REPO}' to ${TARGET_DIR}" >&2
