#!/usr/bin/env bash
# =============================================================================
# grafana-usage-check.sh — the independent "checker AGAINST Grafana".
#
# Grafana watches your apps. This watches the two things that can still cost you
# money, from OUTSIDE the Grafana UI, so a problem with Grafana can't hide inside
# Grafana:
#
#   1. Fleet LLM spend            (the real cash leak: gen_ai_cost_usd_total)
#   2. Grafana Cloud's own usage  (active series -> your Pro bill), if configured
#
# Prints a summary and EXITS NON-ZERO if a threshold is crossed, so it can be
# scheduled (cron / Fly machine / GitHub Action) and alert on failure.
#
# ---- Setup (do this once, in the morning) -----------------------------------
# Mint a READ-scoped Grafana Cloud access policy token (scopes: metrics:read),
# then export these. The Prometheus query URL is on the Grafana Cloud portal:
#   your stack -> Prometheus -> "Details / Sending metrics" -> Query endpoint.
#
#   export GRAFANA_PROM_URL='https://prometheus-prod-XX-us-east-3.grafana.net/api/prom'
#   export GRAFANA_PROM_USER='<metrics instance id>'   # the Prometheus username
#   export GRAFANA_READ_TOKEN='glc_...'                # metrics:read token
#
# Optional — also watch Grafana's own billable usage (active series). The usage
# metrics live in a separate datasource; paste its query URL + user here:
#   export GRAFANA_USAGE_URL='https://prometheus-prod-XX-us-east-3.grafana.net/api/prom'
#   export GRAFANA_USAGE_USER='<usage instance id>'    # often the same id
#
# Thresholds (USD for spend, count for series) — tune to sit under your caps:
#   export SPEND_30D_WARN_USD=120
#   export ACTIVE_SERIES_WARN=8000     # free tier is 10k; Pro bills per series
#
# NOTE: this script was authored but NOT run end-to-end (it needs your read
# token). Verify the URL/user against your Grafana Cloud datasource details on
# first run; the query logic is plain Prometheus instant-queries over curl.
# =============================================================================
set -uo pipefail

SPEND_30D_WARN_USD="${SPEND_30D_WARN_USD:-120}"
ACTIVE_SERIES_WARN="${ACTIVE_SERIES_WARN:-8000}"
status=0

have() { command -v "$1" >/dev/null 2>&1; }

# Extract the scalar value from a Prometheus instant-query JSON response.
# Prefers jq, falls back to python3, then a crude grep.
scalar() {
  if have jq; then
    jq -r '.data.result[0].value[1] // "NaN"' 2>/dev/null
  elif have python3; then
    python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d["data"]["result"][0]["value"][1])
except Exception:
    print("NaN")'
  else
    grep -oE '"value":\[[0-9.]+,"[0-9.eE+-]+"\]' | grep -oE '"[0-9.eE+-]+"\]$' | tr -d '"]'
  fi
}

# query <url> <user> <token> <promql>  -> prints scalar value (or "NaN")
query() {
  local url="$1" user="$2" token="$3" promql="$4"
  curl -s -G "${url}/api/v1/query" \
    --user "${user}:${token}" \
    --data-urlencode "query=${promql}" | scalar
}

bad() { printf '  \033[31m! %s\033[0m\n' "$1"; status=1; }
ok()  { printf '  \033[32mok\033[0m %s\n' "$1"; }

echo "== Checker against Grafana =="

# ---- 1. Fleet LLM spend (the cash leak) -------------------------------------
if [ -n "${GRAFANA_PROM_URL:-}" ] && [ -n "${GRAFANA_PROM_USER:-}" ] && [ -n "${GRAFANA_READ_TOKEN:-}" ]; then
  spend=$(query "$GRAFANA_PROM_URL" "$GRAFANA_PROM_USER" "$GRAFANA_READ_TOKEN" \
                'sum(increase(gen_ai_cost_usd_total[30d]))')
  if [ "$spend" = "NaN" ] || [ -z "$spend" ]; then
    bad "fleet 30d spend: no data (no cost metric yet, or wrong URL/token)"
  else
    printf '  fleet LLM spend, 30d: $%.2f (warn at $%s)\n' "$spend" "$SPEND_30D_WARN_USD" 2>/dev/null \
      || echo "  fleet LLM spend, 30d: \$$spend (warn at \$$SPEND_30D_WARN_USD)"
    awk "BEGIN{exit !($spend > $SPEND_30D_WARN_USD)}" && bad "30d spend over \$$SPEND_30D_WARN_USD" || ok "spend under threshold"
  fi
else
  echo "  (skipped LLM-spend check: set GRAFANA_PROM_URL / GRAFANA_PROM_USER / GRAFANA_READ_TOKEN)"
fi

# ---- 2. Grafana Cloud's own usage (the Pro bill) ----------------------------
if [ -n "${GRAFANA_USAGE_URL:-}" ] && [ -n "${GRAFANA_USAGE_USER:-}" ] && [ -n "${GRAFANA_READ_TOKEN:-}" ]; then
  series=$(query "$GRAFANA_USAGE_URL" "$GRAFANA_USAGE_USER" "$GRAFANA_READ_TOKEN" \
                 'grafanacloud_instance_active_series')
  if [ "$series" = "NaN" ] || [ -z "$series" ]; then
    bad "active series: no data (check usage URL/user, or metric name)"
  else
    printf '  Grafana active series: %.0f (warn at %s)\n' "$series" "$ACTIVE_SERIES_WARN" 2>/dev/null \
      || echo "  Grafana active series: $series (warn at $ACTIVE_SERIES_WARN)"
    awk "BEGIN{exit !($series > $ACTIVE_SERIES_WARN)}" && bad "active series over $ACTIVE_SERIES_WARN" || ok "series under threshold"
  fi
else
  echo "  (skipped Grafana-usage check: set GRAFANA_USAGE_URL / GRAFANA_USAGE_USER)"
fi

echo
[ "$status" -eq 0 ] && echo "All checks within thresholds." || echo "THRESHOLD CROSSED — see above."
exit "$status"
