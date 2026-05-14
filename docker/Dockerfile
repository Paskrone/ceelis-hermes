# CEELIS-Custom Hermes Image
# Builds on upstream nousresearch/hermes-agent and bakes in CEELIS-specific
# MCP servers + init.sh patches at image-build time (reproducible, versioned).
#
# Why a custom image: upstream image has node/npm but no CEELIS-MCP packages.
# Pre-baking them avoids the "Hermes installs into /opt/data volume at runtime"
# anti-pattern (volume reset = lost packages, no version pinning, no audit).

ARG UPSTREAM_TAG=latest
FROM nousresearch/hermes-agent:${UPSTREAM_TAG}

USER root

# CEELIS-MCP-Server (global install, baked into image-layer)
RUN npm install -g \
      @k-jarzyna/mcp-miro \
    && npm cache clean --force

# CEELIS-init.sh: injects MCP configs from env into /opt/data/config.yaml on
# every container start (idempotent). Overrides upstream version.
COPY railway/init.sh /opt/hermes/railway/init.sh
RUN chmod +x /opt/hermes/railway/init.sh

USER hermes
