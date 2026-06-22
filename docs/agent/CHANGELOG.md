# Changelog — Fleet Observability

Reverse-chronological log of agent work. Append an entry per unit; keep it terse and
factual (what changed, why, the verifying evidence, the commit). Newest first.

## 2026-06-22

- **Agent harness created** — `docs/agent/HANDOFF.md` (living state + per-site
  onboarding playbook) and this changelog. Strengthened global `CLAUDE.md` with an
  operational "consolidate branches on sight; never create one" rule (Eric's request).
- **Cardinality guard** on metric labels — drops high-card ids (user/session/request/
  client) before export so a buggy site can't explode Grafana series. Verified: a
  metric with `user.id`/`session_id`/`client.ip` exported with only service/model/
  operation surviving. Silenced OTTL boot warnings. `6271e8e`.
- **Grafana Cloud egress live + verified** end-to-end (`prod-us-east-3`); Grafana
  emailed that metrics are live. Cost-control runbook + independent usage checker +
  schedulable canary. `336cfee`.
- **Collector hardened** — bearer auth on OTLP ingest (`401` w/o token, `200` with),
  closed the public Faro/browser port. `d4b275e`.
- **Spine brought up on Fly** earlier in the week (Grafana Alloy collector, dashboards,
  alerts, runbook) — see git log `27d1f96`..`ab9731c`.

- **aigamma.com onboarded** — consolidated `observability`+`site-quality` into a
  single linear `main` (both branches deleted local+remote), fixed `otel.mjs` to send
  the ingest bearer header (`62f7613`), set the 4 OTLP env vars on Netlify, deployed
  (Netlify deploy `62f7613` state=ready, site HTTP 200). Telemetry path verified **$0**
  by calling `recordLlm` directly with dummy tokens (no Anthropic call): `aigamma-verify`
  cost + token + call metrics arrived **authenticated** at the collector. aigamma emits
  exactly `gen_ai_{cost_usd,usage_input_tokens,usage_output_tokens,calls}_total`, the
  metrics the dashboard's panels query.

- **worldthought.com instrumented** (~2,200 chatbots) — cherry-picked the stale
  instrumentation onto current `main` (which was 43 commits ahead of the old
  `observability` branch), fixed `otel.mjs` bearer auth (`5c8efde`), set Netlify OTLP
  env, consolidated to a single linear `main` (deleted `observability` + the
  already-merged `june-2026-expansion`, local+remote). Telemetry path verified **$0**
  (worldthought-verify span arrived authenticated). **Production deploy DEFERRED**:
  worldthought's build runs `scripts/generate-graph.mjs` which reads Pinecone
  (metered), so per the spend rule it was pushed with `[skip ci]` (`03015c9`) — Eric
  deploys when ready (it's the normal build cost). NOTE: worldthought chat spends on
  Voyage + Pinecone + Anthropic, so it needs caps on all three, not just Anthropic.
