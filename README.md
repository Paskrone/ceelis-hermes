# ceelis-hermes

CEELIS-Custom-Image für [nousresearch/hermes-agent](https://github.com/nousresearch/hermes-agent) (intern: Atlas).

Backt CEELIS-spezifische MCP-Server (Miro etc.) und das angepasste `railway/init.sh` (CEELIS-Portal + Miro + Cost-Routing) als Image-Layer ein — vermeidet das Anti-Pattern, Pakete zur Laufzeit ins Volume zu installieren.

## Build & Push

GitHub Actions baut bei jedem Push auf `main` automatisch ein neues Image und pushed nach `ghcr.io/paskrone/ceelis-hermes:latest` (+ commit-SHA-Tag).

Manuell:
```bash
docker build -t ghcr.io/paskrone/ceelis-hermes:latest -f docker/Dockerfile .
```

## Deploy

Im Docker-Compose des VPS (`/srv/hermes/docker-compose.yml`):
```yaml
services:
  hermes:
    image: ghcr.io/paskrone/ceelis-hermes:latest
    # …siehe vault: 10-Projects/CEELIS-Kundenplattform/hetzner-vps.md
```

## ENVs

Erforderlich: `CEELIS_MCP_BEARER`

Optional: `MIRO_ACCESS_TOKEN`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`, `HERMES_DEFAULT_MODEL`, `HERMES_DELEGATION_MODEL`, `HERMES_AUX_MODEL`, `HERMES_AUX_COMPRESSION_MODEL`, `CEELIS_MCP_URL`

Siehe `railway/init.sh` für vollständige Liste + Defaults.

**Bewusst NICHT als ENV:** `ANTHROPIC_API_KEY`. Claude Code (gebakcken ins Image) läuft via **Subscription-Auth**, nicht über API-Key — sonst würde jeder Coding-Turn API-Token frisst statt Pascals Pro/Max-Subscription zu belasten. Setup einmalig nach erstem Container-Start:
```
docker exec -it hermes claude login
```
OAuth Device-Code-Flow: URL + Code anzeigen, im Browser autorisieren, Credential landet in `/opt/data/.claude/` (persistiert über Container-Restarts via Volume).
