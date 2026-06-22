#!/usr/bin/env bash
# Send one synthetic trace + metric + log over OTLP/HTTP to the collector to
# verify the spine end to end, and double as a schedulable CANARY against Grafana.
#
# The trace carries a FAKE secret prompt (gen_ai.prompt.0.content); after the
# collector's redaction processor, `fly logs` shows the span WITHOUT it.
#
# Exit code: 0 if every signal was accepted (2xx), non-zero otherwise — so a
# scheduled run alerts when the pipeline is broken. (Run WITH ALLOY_INGEST_BEARER
# for the canary; omit it to manually prove the 401 — that run exits non-zero,
# which is expected, since the whole point of that run is the rejection.)
#
# Usage:
#   ALLOY_INGEST_BEARER=... COLLECTOR_URL=https://fleet-otel-collector.fly.dev scripts/send-synthetic.sh
#   scripts/send-synthetic.sh https://fleet-otel-collector.fly.dev
set -u

URL="${1:-${COLLECTOR_URL:-https://fleet-otel-collector.fly.dev}}"

# Ingest is bearer-protected: if ALLOY_INGEST_BEARER is set, present it. Leave it
# unset to send unauthenticated — e.g. to prove the collector now answers 401.
AUTH=()
if [ -n "${ALLOY_INGEST_BEARER:-}" ]; then
  AUTH=(-H "Authorization: Bearer ${ALLOY_INGEST_BEARER}")
fi
NOW_NS=$(( $(date +%s) * 1000000000 ))
# 1.5s duration plus an error status (set below) makes the collector's
# tail-sampling keep-errors/keep-slow policies always retain this verification
# span, so it deterministically reaches the debug exporter (a normal 20%-sampled
# span would only show up sometimes).
START_NS=$(( NOW_NS - 1500000000 ))
# Fresh IDs per run: tail_sampling caches one decision per trace ID, so a reused
# ID would inherit an earlier drop decision.
TRACE_ID=$(openssl rand -hex 16 2>/dev/null || head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')
SPAN_ID=$(openssl rand -hex 8 2>/dev/null || head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')

FAIL=0
# post <path> ; OTLP JSON body on stdin. Prints the HTTP code; flags non-2xx.
post() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$URL$1" \
    ${AUTH[@]+"${AUTH[@]}"} -H 'Content-Type: application/json' --data @-)
  echo "  http $code"
  case "$code" in 2*) ;; *) FAIL=1 ;; esac
}

echo "Target: $URL"
echo

echo "== POST /v1/traces (LLM span with a secret prompt that must be redacted) =="
post /v1/traces <<JSON
{ "resourceSpans": [ { "resource": { "attributes": [
  { "key": "service.name", "value": { "stringValue": "synthetic-verify" } },
  { "key": "deployment.environment", "value": { "stringValue": "verify" } } ] },
  "scopeSpans": [ { "spans": [ {
    "traceId": "$TRACE_ID", "spanId": "$SPAN_ID",
    "name": "chat anthropic", "kind": 3,
    "startTimeUnixNano": "$START_NS", "endTimeUnixNano": "$NOW_NS",
    "attributes": [
      { "key": "gen_ai.system", "value": { "stringValue": "anthropic" } },
      { "key": "gen_ai.request.model", "value": { "stringValue": "claude-haiku-4-5" } },
      { "key": "gen_ai.operation.name", "value": { "stringValue": "chat" } },
      { "key": "gen_ai.usage.input_tokens", "value": { "intValue": "1200" } },
      { "key": "gen_ai.usage.output_tokens", "value": { "intValue": "350" } },
      { "key": "gen_ai.prompt.0.content", "value": { "stringValue": "SECRET-PROMPT-SHOULD-BE-REDACTED" } }
    ], "status": { "code": 2 } } ] } ] } ] }
JSON

echo "== POST /v1/metrics (a derived cost sample) =="
post /v1/metrics <<JSON
{ "resourceMetrics": [ { "resource": { "attributes": [
  { "key": "service.name", "value": { "stringValue": "synthetic-verify" } } ] },
  "scopeMetrics": [ { "metrics": [ {
    "name": "gen_ai.cost.usd", "unit": "usd",
    "sum": { "aggregationTemporality": 2, "isMonotonic": true, "dataPoints": [ {
      "asDouble": 0.0024, "timeUnixNano": "$NOW_NS",
      "attributes": [
        { "key": "gen_ai.request.model", "value": { "stringValue": "claude-haiku-4-5" } },
        { "key": "service.name", "value": { "stringValue": "synthetic-verify" } } ] } ] } } ] } ] } ] }
JSON

echo "== POST /v1/logs =="
post /v1/logs <<JSON
{ "resourceLogs": [ { "resource": { "attributes": [
  { "key": "service.name", "value": { "stringValue": "synthetic-verify" } } ] },
  "scopeLogs": [ { "logRecords": [ {
    "timeUnixNano": "$NOW_NS", "severityText": "INFO",
    "body": { "stringValue": "synthetic verification log from send-synthetic.sh" } } ] } ] } ] }
JSON

echo
echo "Watch the collector receive + redact it:  fly logs -a fleet-otel-collector"
echo "Expect span 'chat anthropic' with gen_ai.usage.* present, gen_ai.prompt.0.content ABSENT."
[ "$FAIL" -eq 0 ] || { echo; echo "FAIL: at least one signal was not accepted (non-2xx)."; }
exit "$FAIL"
