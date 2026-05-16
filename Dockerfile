# GitHub Action runtime for tanstack-compromise-checker.
#
# Pinned to a specific Alpine 3.20 multi-arch manifest index digest so the
# runtime cannot be silently re-pointed by an upstream tag move. To bump:
#   docker buildx imagetools inspect alpine:3.20 | grep Digest
# and update both the tag and the @sha256:... pin together.
FROM alpine:3.23.4@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

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

ENTRYPOINT ["/action/entrypoint.sh"]
