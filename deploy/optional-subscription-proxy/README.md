# Subscription-Proxy für Atlas — opt-in, NICHT empfohlen

Dieser Folder zeigt **wie man Atlas auf Anthropic-Subscription routen würde**, statt OpenRouter / pay-per-token API. Ist absichtlich **nicht in der Haupt-`docker-compose.yml`** verdrahtet. Wenn du nichts aktiv tust, bleibt Atlas wie bisher auf OpenRouter (Llama 3.3 für Reasoning, Gemini Flash für Aux).

## Warum nicht empfohlen

Anthropic-Subscription (Pro/Max) ist offiziell für **Claude Code/Desktop UI** gedacht, nicht für programmatischen Multi-Agent-Use. Reverse-engineered Sidecar-Tools wie [`claude-code-router`](https://github.com/musistudio/claude-code-router) bridge OAuth → OpenAI-API-Format, aber:

| Risiko | Auswirkung |
|---|---|
| **ToS-Verletzung** | Anthropic kann's als Subscription-Missbrauch werten → Account-Sperre |
| **Auth-Refresh fragil** | OAuth-Token rotieren ~1×/h, Sidecar muss Refresh-Flow selbst implementieren |
| **Detection-Layer** | Anthropic patcht regelmäßig User-Agent/Header-Sniffing — Sidecar bricht ohne Vorwarnung |
| **Rate-Limits geteilt** | Dein Max-Plan ist pro Account; wenn Atlas + du parallel arbeitet, halbiert sich's |
| **Maintenance** | Community-Projekt, Pin auf konkreten Commit nötig damit's stabil bleibt |

**Saubere Alternativen wenn Cost dich beißt:**
- Atlas-Modell von Llama 3.3 auf Sonnet 4.6 über OpenRouter (~15-30 €/Mo bei moderater Nutzung)
- Oder direkter Anthropic-API-Key (gleicher Preis, weniger Provider-Hop)

## Wenn du es trotzdem ausprobieren willst (Stage-Setup, nicht Production)

### Schritt 1 — Compose-Override aktivieren

In `/srv/hermes/`:
```bash
cd /srv/hermes
# Override neben das Hauptfile legen
cp /home/pascal/ceelis-hermes/deploy/optional-subscription-proxy/docker-compose.override.yml ./
# Compose merged main + override automatisch:
docker compose up -d
```

Docker liest `docker-compose.yml` + `docker-compose.override.yml` zusammen — der CCR-Service kommt dazu, Hermes bekommt die `OPENAI_*`-ENVs.

### Schritt 2 — init.sh-Block austauschen

Statt OpenRouter-Block in `railway/init.sh` (im ceelis-hermes-Repo, dann rebuild) den Inhalt aus [`init-snippet.sh`](init-snippet.sh) reinkopieren. Atlas zeigt dann auf `http://ccr:8080/v1` statt `openrouter.ai`.

### Schritt 3 — Auth bridgen

`docker-compose.override.yml` mountet `/srv/hermes/data/.claude/.credentials.json` read-only in den CCR-Container. CCR liest beim Start das OAuth-Refresh-Token und initialisiert den Token-Refresh-Loop. Wenn `claude login` mal neu gemacht wird, ccr-Container neustarten:
```bash
docker compose restart ccr
```

### Schritt 4 — Verify

```bash
# CCR proxied korrekt?
curl http://178.105.117.237:8080/v1/models -H "Authorization: Bearer dummy"
# sollte JSON mit verfügbaren Claude-Modellen geben

# Atlas spricht jetzt zu CCR?
docker exec hermes grep -A1 "provider:" /opt/data/config.yaml
# sollte zeigen: provider: openai, base_url: http://ccr:8080/v1
```

### Schritt 5 — Wieder zurück zu OpenRouter

```bash
cd /srv/hermes
rm docker-compose.override.yml
# init.sh-Block in ceelis-hermes-Repo zurück auf OpenRouter, rebuild
docker compose up -d
```

## Was du beobachten solltest wenn du's testweise aktivierst

- **Token-Rate-Limit-Errors** — wenn du selbst parallel Claude Code nutzt
- **HTTP 401** in ccr-logs — wenn Auth-Refresh fehlschlägt (`claude login` neu nötig)
- **HTTP 429** — Anthropic-Rate-Limit für Subscription erreicht
- **HTTP 403** in unerwartetem Pattern — kann Detection-Hint sein, Sidecar updaten

## Was wir hier nicht abdecken

- Multi-User-Setup (z. B. Luis als zweiter Atlas-Konsument)
- Custom-Model-Routing pro Skill (CCR unterstützt Per-Request-Model)
- Logging / Cost-Estimation pro Atlas-Turn

Wenn du irgendwann ernsthaft erwägst zu wechseln: vorher den hermes-agent-Maintainer fragen ob es einen eingebauten „Subscription-Provider"-Pfad gibt. Vermutlich nein (gleiches ToS-Issue), aber Stand der Software ändert sich.
