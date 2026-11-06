FROM alpine:3.24.3

LABEL org.opencontainers.image.title="aicage-image-util credential agent" \
      org.opencontainers.image.description="Credential-agent sidecar for aicage" \
      org.opencontainers.image.source="https://github.com/aicage/aicage-image-util" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN apk add --no-cache \
    gnupg \
    openssh-client

COPY images/credential-agent/aicage-credential-agent /usr/local/bin/aicage-credential-agent
COPY images/credential-agent/aicage-credential-agent-ssh /usr/local/bin/aicage-credential-agent-ssh
COPY images/credential-agent/aicage-credential-agent-gpg /usr/local/bin/aicage-credential-agent-gpg
COPY images/credential-agent/aicage-credential-agent-askpass /usr/local/bin/aicage-credential-agent-askpass

RUN chmod 0755 /usr/local/bin/aicage-credential-agent \
    /usr/local/bin/aicage-credential-agent-ssh \
    /usr/local/bin/aicage-credential-agent-gpg \
    /usr/local/bin/aicage-credential-agent-askpass

ENTRYPOINT ["aicage-credential-agent"]
