#!/bin/bash
# OPT-IN ALTERNATIVE: Atlas-Config wenn CCR-Sidecar aktiv ist.
#
# Diesen Block in railway/init.sh REPLACEMENT für den OpenRouter-Block einsetzen
# (von "config['model']['provider'] = 'openrouter'" bis "config['provider_routing']").
# Dann Image rebuilden + pullen + recreate.

# === REPLACEMENT für OpenRouter-Block in init.sh ===
# (in der python-Heredoc, statt der aktuellen openrouter-config)

# --- Atlas spricht über CCR-Sidecar mit Anthropic-Subscription ---
# CCR emuliert OpenAI-API-Format, ist aber Anthropic im Backend.
config["model"]["provider"] = "openai"
config["model"]["base_url"] = os.environ.get("OPENAI_BASE_URL", "http://ccr:8080/v1")
config["model"]["api_key"] = os.environ.get("OPENAI_API_KEY", "dummy-not-used")

# Anthropic-Model-IDs direkt (statt OpenRouter-Schreibweise mit Provider-Prefix)
config["model"]["roles"] = {
    "explorer": "claude-haiku-4-5",     # billig+schnell für Recherche-Sub-Agents
    "planner": "claude-sonnet-4-6",     # mittlere Komplexität
    "executor": "claude-sonnet-4-6",    # Standard-Execution
    "reviewer": "claude-opus-4-7",      # höchste Quality für Code-Review
    "vision": "claude-sonnet-4-6",      # Sonnet hat solide Vision-Capabilities
}
config["model"]["fallback"] = [
    "claude-haiku-4-5",                  # Fallback wenn höhere Tiers rate-limited
]
changes.append("model.provider=openai (via CCR), claude-direct model-IDs")

# provider_routing entfällt — kein OpenRouter mehr, also kein Aufschlag-Mapping nötig
# (lass den Block nicht stehen, sonst verwirrt es CCR)

# === Aux-Models bleiben auf OpenRouter (Gemini Flash + Pro) ===
# Vision/Web/Title-Gen über Subscription wäre Overkill — Aux-Block unverändert
# lassen. CCR routet nur die "main"-Calls, OpenRouter macht die Aux-Trivia.
# (Setzt voraus dass OPENROUTER_API_KEY noch in der .env steht.)

# === ENDE Replacement ===

# Hinweis: HERMES_DEFAULT_MODEL und HERMES_DELEGATION_MODEL in .env
# müssen auch auf Anthropic-IDs umgestellt werden:
#   HERMES_DEFAULT_MODEL=claude-sonnet-4-6
#   HERMES_DELEGATION_MODEL=claude-haiku-4-5
