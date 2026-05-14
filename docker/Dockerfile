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
# Note: hermes' MCP-Subprocess-Startup triggert `npm install --global` als
# Update-Check für globally installierte Packages. Das scheitert mit EACCES weil
# der Container als unprivileged hermes-User (UID 10000) auf root-owned npm-paths
# läuft (~36 Log-Zeilen pro Start). Funktional unkritisch — MCP startet trotzdem
# über den bereits installierten Pfad. KEIN chown-Workaround hier, damit das
# Custom-Image minimal-divergent zu upstream bleibt. Upstream-Issue siehe
# nousresearch/hermes-agent#18800.
RUN npm install -g \
      @k-jarzyna/mcp-miro \
      @anthropic-ai/claude-code \
    && npm cache clean --force

# CEELIS-init.sh: injects MCP configs from env into /opt/data/config.yaml on
# every container start (idempotent). Overrides upstream version.
COPY railway/init.sh /opt/hermes/railway/init.sh
RUN chmod +x /opt/hermes/railway/init.sh

USER hermes
