# Development

## Local build

```bash
cd aicage-image-util
docker build -t ghcr.io/aicage/aicage-image-util:agent-version .
```

## CI publish

GitHub Actions builds weekly, on tag pushes, or on manual runs. It publishes multi-arch images for
amd64 and arm64 after signing and verifying. The final tags are
`ghcr.io/aicage/aicage-image-util:<ref>` and `ghcr.io/aicage/aicage-image-util:agent-version`.

## Image scope

This repo intentionally ships small, purpose-scoped images. Keep new images tagged by purpose
instead of `latest`.
