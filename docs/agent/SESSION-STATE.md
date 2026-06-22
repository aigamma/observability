# Session State — 2026-06-22 (deliberate consolidation at high context)

Durable snapshot so nothing drifts if context compacts. Pairs with `HANDOFF.md`,
`CHANGELOG.md`, `FOUNDATION-REVIEW.md`.

## All repos committed + pushed (HEAD==origin)
- **observability** `643730e` — collector hardened + egress live; foundation review;
  token/canary/doc fixes; **log redaction deployed** (verify pending).
- **aigamma.com** `7b51749`, **worldthought.com** `725c301` — token-panel fix, **deploying** (Netlify).
- **ai-firehose.com** `a3bb419` — worker token fix (takes effect on next worker run).
- **spokenhistory.org** master `655aabe` — `retrieve.mjs` instrumented (Voyage embed+rerank);
  **DORMANT** until its Netlify OTEL env is set + redeploy.

## Done this session
- Full **foundation review** (5 dimensions) — `FOUNDATION-REVIEW.md` + `foundation-review-findings.json`.
- FIXED + deployed: README `free tier→Pro`; verify-command needs bearer; ONBOARDING Faro URL on
  closed port; **token/calls dashboard panels** (dropped the unit so OTLP→Prom stops appending
  `_token`/`_call`, in all 4 emitters); canary emits `deployment.environment`; **log redaction**.
- aigamma + worldthought live + instrumented; ai-firehose worker wired; spokenhistory instrumented.
- Global **status line** now counts active agents by liveness (0 when idle) + `refreshInterval`.

## Co-strategy backlog (DEFERRED — needs Eric's strategic input; do NOT apply blind)
1. **Egress durability** — otlphttp exporter has no `sending_queue`/`file_storage` → telemetry
   dropped on a Cloud outage or machine-suspend. Add a file-backed queue.
2. **Ingest rate-limiting** — bearer gates *who*, nothing gates *how much* (flood→paid-ingest risk).
3. **Per-site ingest bearer** (vs. one shared; `service.name` is self-asserted/spoofable; rotation).
4. **Remove debug exporter + `--stability.level=experimental`** post-verification (CPU/log/PII cost).
5. **memory_limiter** 180+40MiB is tight on the 256MB box (OOM risk) — lower it or bump the VM.
6. **Alerts**: "month to date" is really trailing-30d (vs calendar-month provider caps); add a
   short-window rate-of-spend/acceleration alert.

## Pending verification / activation (Eric or data-gated)
- Token-panel fix: confirm in Grafana once aigamma/worldthought finish deploying + data flows.
- Log redaction: send a log carrying a `gen_ai.prompt.*` attr → confirm it's stripped.
- spokenhistory: set Netlify env (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`=the
  ingest bearer, `OTEL_SERVICE_NAME=spokenhistory`, `DEPLOY_ENV=prod`) → redeploy → $0 verify.
- **learnrust.ai** (Rust recipe) — not started.
- **THE GOAL**: Eric sets provider caps (incl Voyage/Pinecone) + raises the Anthropic limit →
  real per-operation cost flows → the leak names itself on `dashboards/llm-cost.json`.
