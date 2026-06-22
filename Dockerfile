# GitHub Action runtime for tanstack-compromise-checker.
#
# Pinned to a specific Alpine 3.20 multi-arch manifest index digest so the
# runtime cannot be silently re-pointed by an upstream tag move. To bump:
#   docker buildx imagetools inspect alpine:3.20 | grep Digest
# and update both the tag and the @sha256:... pin together.
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

RUN apk add --no-cache \
      bash \
      curl \
      jq \
      findutils \
      grep \
      sed \
      python3 \
      coreutils \
      git

WORKDIR /action
COPY check.sh /action/check.sh
COPY entrypoint.sh /action/entrypoint.sh
RUN chmod +x /action/check.sh /action/entrypoint.sh

# Run as a non-root user. UID 1001 matches the GitHub Actions runner UID that
# owns $GITHUB_WORKSPACE, so the entrypoint can write findings JSON without
# ownership gymnastics. For ad-hoc `docker run` on hosts where the bind-mount
# is owned by a different UID, pass `--user 0` or chmod the mount first.
RUN addgroup -S tcc -g 1001 && adduser -S -G tcc -u 1001 -h /home/tcc -s /bin/bash tcc \
    && chown -R 1001:1001 /action
USER 1001:1001

ENTRYPOINT ["/action/entrypoint.sh"]
