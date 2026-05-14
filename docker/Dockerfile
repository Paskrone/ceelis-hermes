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

# CEELIS-MCP-Server + Claude Code CLI (global install, baked into image-layer)
# Claude Code wird von Atlas via skill `claude-code` aufgerufen (Print Mode `claude -p ...`).
# Auth läuft über Subscription (`docker exec -it hermes claude login` einmalig).
#
# chown auf hermes-User (UID 10000) — bekanntes Hermes-Verhalten (Issue #18800):
# hermes' TUI-Launcher + MCP-Subprocess-Startup macht `npm install` bei jedem
# Container-Start als Update-Check. Ohne write-perms scheitert das mit EACCES
# (Log-Noise, aber funktional unkritisch). chown behebt das.
RUN npm install -g \
      @k-jarzyna/mcp-miro \
      @anthropic-ai/claude-code \
    && npm cache clean --force \
    && chown -R 10000:10000 \
         /usr/local/lib/node_modules/@k-jarzyna \
         /usr/local/lib/node_modules/@anthropic-ai \
         /usr/local/lib/node_modules/.package-lock.json 2>/dev/null || true

# CEELIS-init.sh: injects MCP configs from env into /opt/data/config.yaml on
# every container start (idempotent). Overrides upstream version.
COPY railway/init.sh /opt/hermes/railway/init.sh
RUN chmod +x /opt/hermes/railway/init.sh

USER hermes
