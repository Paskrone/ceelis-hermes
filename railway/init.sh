#!/bin/bash
# CEELIS-Hermes-Init: Injects CEELIS-MCPs + Anthropic-Provider + STT/Auxiliary settings
# into hermes config.yaml.
#
# Runs every container start as the hermes user (after docker/entrypoint.sh
# has bootstrapped defaults). Idempotent: overwrites our managed sections,
# preserves everything else the user may have set via `hermes config set`.
#
# Required ENVs:
#   CEELIS_MCP_BEARER
# Optional ENVs:
#   CEELIS_MCP_URL          (default: https://api.kundenportal.ceelis.com/functions/v1/mcp)
#   MIRO_ACCESS_TOKEN       (presence → mcp_servers.miro injected, package from image)
#   HERMES_DEFAULT_MODEL    (presence → overrides model.default in config.yaml on every boot)
#   HERMES_DELEGATION_MODEL (presence → sets delegation.model for cheap sub-agent task offload)
#   GROQ_API_KEY            (presence → STT-Provider switched to groq)
#   OPENROUTER_API_KEY      (presence → auxiliary side-tasks routed to OpenRouter/Gemini-Flash)
#   HERMES_AUX_MODEL        (default: google/gemini-2.5-flash — used for vision/web/search/titles/approval/triage)
#   HERMES_AUX_COMPRESSION_MODEL (default: google/gemini-2.5-pro — needs >= main-model context window)
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"

# Claude-Code-Subscription-Credentials für Atlas-Subprocesses erreichbar machen.
# Upstream entrypoint.sh setzt für Atlas' Subprocesses HOME=/opt/data/home (per-profile
# HOME, damit git/ssh/npm in persistentes Volume schreiben statt nach /root). Claude-Code
# sucht aber Credentials in $HOME/.claude/.credentials.json — der `docker exec claude login`
# hat sie nach /opt/data/.claude/.credentials.json gelegt (default-HOME beim exec). Ohne
# Symlink würde Atlas im Subprocess "Not logged in" sehen.
mkdir -p "$HERMES_HOME/home/.claude" "$HERMES_HOME/.claude"
ln -sfn "$HERMES_HOME/.claude/.credentials.json" "$HERMES_HOME/home/.claude/.credentials.json"

# Claude-Code-Settings pinnen (Opus 4.7 als Default-Model, sonst wäre Atlas
# anfällig wenn Anthropic die Plan-Defaults später ändert). Idempotent —
# überschreibt nur wenn nicht da oder veraltet.
if [ ! -f "$HERMES_HOME/.claude/settings.json" ] || \
   ! grep -q '"model".*claude-opus-4-7' "$HERMES_HOME/.claude/settings.json" 2>/dev/null; then
    cat > "$HERMES_HOME/.claude/settings.json" <<'CLAUDE_SETTINGS'
{
  "theme": "dark",
  "model": "claude-opus-4-7"
}
CLAUDE_SETTINGS
fi
ln -sfn "$HERMES_HOME/.claude/settings.json" "$HERMES_HOME/home/.claude/settings.json"

python3 <<PYEOF
import os, yaml
from pathlib import Path

path = Path(os.environ.get("HERMES_HOME", "/opt/data")) / "config.yaml"
config = {}
if path.exists():
    try:
        config = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as e:
        print(f"[ceelis-init] WARNING: existing config.yaml unparseable ({e}), starting fresh")
        config = {}

changes = []

# --- Main model — IMMER aus ENV setzen wenn vorhanden (überschreibt existing) ---
config.setdefault("model", {})
if os.environ.get("HERMES_DEFAULT_MODEL"):
    config["model"]["default"] = os.environ["HERMES_DEFAULT_MODEL"]
    changes.append(f"model.default={config['model']['default']}")

# --- Cost-optimized config block (Pascal explicit 2026-05-14) ---
config["model"]["provider"] = "openrouter"
config["model"]["roles"] = {
    "explorer": "qwen/qwen3-coder:free",
    "planner": "minimax/minimax-m2.7",
    "executor": "deepseek/deepseek-v4-flash",
    "reviewer": "moonshotai/kimi-k2.6",
    "vision": "google/gemma-4-26b-a4b-it:free",
}
config["model"]["fallback"] = [
    "deepseek/deepseek-v4-flash",
    "google/gemma-3-12b-it:free",
]
changes.append("model.provider=openrouter, model.roles, model.fallback")

config["provider_routing"] = {
    "sort": "price",
    "data_collection": "deny",
    "require_parameters": True,
}
changes.append("provider_routing")

config["compression"] = {
    "enabled": True,
    "threshold": 0.50,
}
changes.append("compression.threshold=0.50")

# --- Delegation model — für sub-agent task offload auf günstigerem Modell ---
if os.environ.get("HERMES_DELEGATION_MODEL"):
    config.setdefault("delegation", {})
    config["delegation"]["model"] = os.environ["HERMES_DELEGATION_MODEL"]
    changes.append(f"delegation.model={config['delegation']['model']}")

# --- CEELIS-Portal-MCP (immer aus ENV neu setzen — Bearer kann rotieren) ---
if os.environ.get("CEELIS_MCP_BEARER"):
    config.setdefault("mcp_servers", {})
    config["mcp_servers"]["ceelis-portal"] = {
        "url": os.environ.get("CEELIS_MCP_URL", "https://api.kundenportal.ceelis.com/functions/v1/mcp"),
        "headers": {"Authorization": f"Bearer {os.environ['CEELIS_MCP_BEARER']}"},
        "enabled": True,
    }
    changes.append("mcp_servers.ceelis-portal")
else:
    print("[ceelis-init] CEELIS_MCP_BEARER missing — skipping CEELIS-MCP injection.")

# --- Miro MCP (package from image-layer via npx -y, token from ENV) ---
# Anders als ceelis-portal (HTTPS-MCP) ist miro ein stdio-MCP-Subprocess. Package
# wird via `npm install -g @k-jarzyna/mcp-miro` im Dockerfile gebacken, also liegt
# es unter /usr/local/lib/node_modules/ und `npx -y` resolved local-first.
if os.environ.get("MIRO_ACCESS_TOKEN"):
    config.setdefault("mcp_servers", {})
    config["mcp_servers"]["miro"] = {
        # Direkter Node-Pfad statt `npx -y` — npx versucht beim Start in den
        # globalen node_modules zu schreiben (Update-Check), was als hermes-User
        # (UID 10000) auf einem root-installierten Image-Layer fehlschlägt.
        "command": "node",
        "args": ["/usr/local/lib/node_modules/@k-jarzyna/mcp-miro/build/index.js"],
        "env": {"MIRO_ACCESS_TOKEN": os.environ["MIRO_ACCESS_TOKEN"]},
        "enabled": True,
    }
    changes.append("mcp_servers.miro")

# --- STT: switch to groq if API-Key present ---
if os.environ.get("GROQ_API_KEY"):
    config.setdefault("stt", {})
    config["stt"]["enabled"] = True
    config["stt"]["provider"] = "groq"
    changes.append("stt.provider=groq")

# --- Auxiliary models: route side-tasks to OpenRouter/Gemini-Flash if key present ---
if os.environ.get("OPENROUTER_API_KEY"):
    aux_model = os.environ.get("HERMES_AUX_MODEL", "google/gemini-2.5-flash")
    aux_compression_model = os.environ.get("HERMES_AUX_COMPRESSION_MODEL", "google/gemini-2.5-pro")
    config.setdefault("auxiliary", {})
    for task in ("vision", "web_extract", "session_search", "title_generation", "approval", "triage_specifier"):
        config["auxiliary"][task] = {"provider": "openrouter", "model": aux_model}
    config["auxiliary"]["compression"] = {"provider": "openrouter", "model": aux_compression_model}
    changes.append(f"auxiliary.*=openrouter/{aux_model} (compression={aux_compression_model})")

path.write_text(yaml.safe_dump(config, sort_keys=False, default_flow_style=False))
print(f"[ceelis-init] config.yaml updated at {path}: {', '.join(changes) if changes else 'no changes'}")
PYEOF

# Dashboard NACH config.yaml-Inject backgrounden (statt durch upstream entrypoint.sh
# VOR init.sh) — sonst liest das Dashboard die bootstrap-config.yaml mit `command: npx`
# und triggert `npm install`, scheitert mangels Schreibrechten.
# Voraussetzung: HERMES_DASHBOARD=0 in env_file (upstream entrypoint.sh überspringt dann).
case "${CEELIS_DASHBOARD:-1}" in
    1|true|TRUE|True|yes|YES|Yes)
        dash_host="${CEELIS_DASHBOARD_HOST:-0.0.0.0}"
        dash_port="${CEELIS_DASHBOARD_PORT:-9119}"
        echo "[ceelis-init] starting hermes dashboard on ${dash_host}:${dash_port} (background)"
        (
            stdbuf -oL -eL hermes dashboard --host "$dash_host" --port "$dash_port" --no-open --insecure 2>&1 \
                | sed -u 's/^/[dashboard] /'
        ) &
        ;;
esac

# Final: execute hermes with the args we were called with
exec hermes "$@"
