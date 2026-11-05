# Development

## Local build

```bash
cd aicage-image-util
docker build -f images/agent-version/Dockerfile -t ghcr.io/aicage/aicage-image-util:agent-version .
docker build -f images/credential-agent/Dockerfile -t ghcr.io/aicage/aicage-image-util:credential-agent .
```

## CI publish

GitHub Actions builds weekly, on tag pushes, or on manual runs. It publishes multi-arch images for
amd64 and arm64 after signing and verifying. Each image receives a purpose-qualified version tag and stable tag:
`ghcr.io/aicage/aicage-image-util:agent-version-<ref>` and
`ghcr.io/aicage/aicage-image-util:agent-version`, or
`ghcr.io/aicage/aicage-image-util:credential-agent-<ref>` and
`ghcr.io/aicage/aicage-image-util:credential-agent`.

## Image scope

This repo intentionally ships small, purpose-scoped images. Keep new images tagged by purpose
instead of `latest`.
