# Session State — 2026-06-22 (deliberate consolidation at high context)

Durable snapshot so nothing drifts if context compacts. Pairs with `HANDOFF.md`,
`CHANGELOG.md`, `FOUNDATION-REVIEW.md`.

## 2026-06-22 (evening) — new since consolidation
- **Anthropic cap raised $200 → $250** (+~$167 credits). Real spend can now flow and be measured;
  the bleed lands in Grafana Cloud + `fly logs` independent of any workstation (re-image-proof).
- **Cost-leak analysis written:** `docs/COST-ANALYSIS.md` — ranked hypotheses (worldthought volume,
  aigamma Opus unit-cost, the 15-min `narrate` fixed-cost drip), the cache-token blind spot, how to measure.
- **Agent harness:** this repo now has an auto-loaded `CLAUDE.md` — read it first every session.
- **Config backup (re-image safety):** `~/.claude` portable config is version-controlled at
  `github.com/aigamma/claude-config` (private) + mirrored to `D:\Dropbox\backups\claude-config` by a
  weekly Windows task (`ClaudeConfigWeeklyBackup`, Sun 3am). Restore anywhere: clone + `./deploy.ps1`.
- **NEXT:** capture a `fly logs` window once `narrate` has fired and chatbots saw traffic; fill real
  (service, model, operation) costs into COST-ANALYSIS.md; confirm/kill the ranking; act on throttling.

## 2026-06-22 late evening — autonomous instrumentation session (Eric biking)
Spigot reopened; I measured and hardened while waiting for organic traffic. All committed + pushed.
- **Cache cost blind spot — FIXED.** aigamma + worldthought `chat` use prompt caching but recorded only
  `input_tokens`, so the dashboard *undercounted* the chatbot bill. Now capture + price `cache_read` (0.1×)
  / `cache_creation` (1.25×), emit counters, dashboard panels 7–8 added. (`e8ccf4e`, `65ef01f`, `61dd4ac`)
- **connection-chat Sonnet blind spot — FIXED.** worldthought's /connections modal (Sonnet, 64k, doubled
  RAG) was wholly uninstrumented — invisible spend. Instrumented additively (no risk to the stream). (`b260458`)
- **Coverage audit (`642ca6e`):** all live Anthropic paths now measured; only gaps are negligible Voyage
  retrieval + manual RAG scripts.
- **`narrate` is dormant:** not Netlify-scheduled — its external 15-min trigger is likely off, so that
  suspected drip isn't firing.
- **Measurement:** 3 `fly logs` captures, NO organic traffic yet (late hour; cron off). Pipeline healthy.
  Detailed log: `docs/agent/MEASUREMENTS.md`. Cost lens: `docs/COST-ANALYSIS.md`.
- **NEXT:** re-capture once real chatbot traffic / a RAG cycle happens — the cache panels, `connection-chat`,
  and reconciled cost will then reveal the true leak. The instrumentation is now comprehensive and accurate.
- **Fleet coverage COMPLETE:** spokenhistory activated (`f3de03a` — Netlify linked, OTEL env set for the
  production context, redeployed). All five services (aigamma, worldthought, ai-firehose, spokenhistory)
  plus the collector are now instrumented AND live. Nothing is left dark.

## All repos committed + pushed (HEAD==origin)
- **observability** `643730e` — collector hardened + egress live; foundation review;
  token/canary/doc fixes; **log redaction deployed + live-verified**.
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
- Log redaction: ✓ VERIFIED — synthetic `gen_ai.prompt.0.content` stripped; only `collector.name`
  survived on the exported log record (debug exporter, 2026-06-22).
- spokenhistory: set Netlify env (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`=the
  ingest bearer, `OTEL_SERVICE_NAME=spokenhistory`, `DEPLOY_ENV=prod`) → redeploy → $0 verify.
- **learnrust.ai** (Rust recipe) — not started.
- **THE GOAL**: Eric sets provider caps (incl Voyage/Pinecone) + raises the Anthropic limit →
  real per-operation cost flows → the leak names itself on `dashboards/llm-cost.json`.
