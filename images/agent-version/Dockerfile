FROM node:alpine

LABEL org.opencontainers.image.title="aicage-image-util" \
      org.opencontainers.image.description="Utility image for aicage runtime tasks" \
      org.opencontainers.image.source="https://github.com/aicage/aicage-image-util" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    py3-pip \
    python3 \
    tar \
    unzip \
    xz \
    yq

CMD ["/bin/sh"]
