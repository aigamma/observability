# Changelog — Fleet Observability

Reverse-chronological log of agent work. Append an entry per unit; keep it terse and
factual (what changed, why, the verifying evidence, the commit). Newest first.

## 2026-06-22

- **ai-firehose worker wired** — fixed its otel.mjs bearer auth (`f33b7593c`), staged its
  Fly OTEL env, verified the path $0 (`ai-firehose-verify` voyage-3 metrics arrived
  authenticated). Already well-instrumented (recordLlm in voyage.mjs + anthropic.mjs).
  Deploy/ingestion-run deferred to the Anthropic limit-raise so the full cycle runs measured.
- **Global agent-count status line shipped** — added an `agents` column to the user's
  existing `~/.claude/statusline.py`, computed from VERIFIED transcript markers (background
  `agentId:` launches minus completion notifications + synchronous Agent tool_use without a
  result) — NOT the research subagent's hallucinated `SubagentStart`/`hook_invocation`
  markers (not real entry types; would always show 0). Tested: 0 on the real transcript, 1
  on a synthetic active case. Global via settings.json (all repos).
- **worldthought.com DEPLOYED** (`66752b4`) — Eric returned, authorized all infra/build
  spend, so the `[skip ci]` hold was removed and it deployed (Netlify state=ready). Both
  prime suspects (aigamma + worldthought) now live + instrumented.
- **Statusline task started** — Eric lost an all-day Claude Code session when the agent
  panel crashed PowerShell on a left-arrow; wants a GLOBAL statusline showing the active-
  agent count. Researching the reliable mechanism (does the statusLine stdin expose it,
  or derive from transcript?) before configuring + testing.
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
