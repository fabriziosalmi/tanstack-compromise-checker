# GitHub Action runtime for tanstack-compromise-checker.
#
# Pinned to a specific Alpine 3.20 multi-arch manifest index digest so the
# runtime cannot be silently re-pointed by an upstream tag move. To bump:
#   docker buildx imagetools inspect alpine:3.20 | grep Digest
# and update both the tag and the @sha256:... pin together.
FROM alpine:3.20.10@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc

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
