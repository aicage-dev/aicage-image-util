FROM alpine:3.24.3

LABEL org.opencontainers.image.title="aicage-image-util credential agent" \
      org.opencontainers.image.description="Credential-agent sidecar for aicage" \
      org.opencontainers.image.source="https://github.com/aicage/aicage-image-util" \
      org.opencontainers.image.licenses="Apache-2.0"

# GnuPG: gnupg. SSH: openssh-client.
RUN apk add --no-cache \
    gnupg \
    openssh-client \
    socat

# Credential-agent commands and private protocol implementations.
COPY images/credential-agent/usr-local/ /usr/local/

ENTRYPOINT ["credential-agent"]
