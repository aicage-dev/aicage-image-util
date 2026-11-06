# aicage-image-util

Utility images used by the `aicage` CLI at runtime and for local workflows.

## Images

### agent-version

Runs agent `version.sh` scripts in a controlled toolchain.

Includes: `bash`, `curl`, `git`, `jq`, `tar`, `python3`, `pip`, `nodejs`, `npm`.

Published tag: `ghcr.io/aicage/aicage-image-util:agent-version`.

Example usage from the `aicage` repo root:

```bash
docker run --rm \
  -v "$(pwd)/aicage-image/agents/claude:/agent:ro" \
  ghcr.io/aicage/aicage-image-util:agent-version \
  /bin/bash /agent/version.sh
```
