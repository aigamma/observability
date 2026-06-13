#!/usr/bin/env bash
# Send one synthetic trace + metric + log over OTLP/HTTP to the collector, to
# verify the Wave 0 spine end to end. The trace carries a FAKE secret prompt
# attribute (gen_ai.prompt.0.content); after it passes through the collector's
# redaction processor, `fly logs` should show the span WITHOUT that attribute.
#
# Usage:
#   COLLECTOR_URL=https://fleet-otel-collector.fly.dev scripts/send-synthetic.sh
#   scripts/send-synthetic.sh https://fleet-otel-collector.fly.dev
set -u

URL="${1:-${COLLECTOR_URL:-https://fleet-otel-collector.fly.dev}}"
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

echo "Target: $URL"
echo

echo "== POST /v1/traces (LLM span with a secret prompt that must be redacted) =="
curl -s -o /dev/null -w "  http %{http_code}\n" -X POST "$URL/v1/traces" \
  -H 'Content-Type: application/json' \
  --data @- <<JSON
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
curl -s -o /dev/null -w "  http %{http_code}\n" -X POST "$URL/v1/metrics" \
  -H 'Content-Type: application/json' \
  --data @- <<JSON
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
curl -s -o /dev/null -w "  http %{http_code}\n" -X POST "$URL/v1/logs" \
  -H 'Content-Type: application/json' \
  --data @- <<JSON
{ "resourceLogs": [ { "resource": { "attributes": [
  { "key": "service.name", "value": { "stringValue": "synthetic-verify" } } ] },
  "scopeLogs": [ { "logRecords": [ {
    "timeUnixNano": "$NOW_NS", "severityText": "INFO",
    "body": { "stringValue": "synthetic verification log from send-synthetic.sh" } } ] } ] } ] }
JSON

echo
echo "Now watch the collector receive + redact it:"
echo "  fly logs -a fleet-otel-collector"
echo "Expect the span 'chat anthropic' with gen_ai.usage.* present and"
echo "gen_ai.prompt.0.content ABSENT (redaction proven)."
