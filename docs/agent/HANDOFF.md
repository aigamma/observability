# Agent Handoff — Fleet Observability

**Living state + playbook for the next agent and for Eric. Keep this current as you work.**
This is the "agent harness": read it first, do the next undone thing, update it, commit.

## Mission
Find and stop a runaway LLM-API **cash/cache leak**. This repo is the OpenTelemetry
spine that measures per-service / model / operation cost so the leak becomes visible;
then throttle or retire the offenders. Eric pays for Grafana Cloud Pro (US-East/VA),
is new to Grafana, and this is becoming a multi-month, career-defining project. For
now: get a full-stack proof of concept live, then troubleshoot the bleed.

## Operating rules that shape everything (from global CLAUDE.md)
- **Spend discipline.** Never run project code that hits a paid LLM API without
  Eric's OK. **Anthropic is currently MAXED at its monthly limit**, so aigamma.com +
  worldthought.com (Anthropic-only chatbots) physically cannot spend — deploying
  their instrumentation is **$0**. Do NOT raise the Anthropic limit (Eric's action,
  planned +$50 tonight). Do NOT trigger any site that uses a non-maxed provider
  (the ai-firehose worker uses Voyage/OpenAI/Pinecone — leave it alone).
- **No branches, ever.** Consolidate any branch onto `main` and delete it. Never
  `checkout -b` / `switch -c` / `worktree add`, never a PR.
- **Sequential + commit each unit.** Onboard one site, commit & push, then the next.
  A crash must cost at most the one in-flight site. Swarms/Workflow are authorized
  (Eric, 2026-06-22, "zero concern about usage") but ONLY for read-only breadth
  (audits, leak-hunt) — never for parallel mutations (lost-work + cross-contamination).
- **Evidence over assurance.** Verify against an oracle (HTTP code, `fly logs`,
  build exit) before claiming done.

## Current verified state (2026-06-22)
- Collector `fleet-otel-collector` (Grafana Alloy on Fly `iad`): **LIVE + hardened.**
  - OTLP ingest bearer-authed: `401` without token, `200` with. Secret name
    `ALLOY_INGEST_BEARER` (in Fly secrets + each site's `OTEL_EXPORTER_OTLP_HEADERS`;
    NOT in git).
  - Egress to Grafana Cloud `prod-us-east-3` verified end-to-end (Grafana emailed
    that metrics are live).
  - Prompt redaction + metric-cardinality guard active; public Faro port closed.
- Endpoint for sites: `OTEL_EXPORTER_OTLP_ENDPOINT=https://fleet-otel-collector.fly.dev`
- Runbooks: `docs/COST-CONTROLS.md` (layered defense + checker-against-Grafana),
  `docs/ONBOARDING.md` (per-runtime recipes). Canary: `scripts/send-synthetic.sh`
  (exits non-zero on failure). Independent usage watch: `scripts/grafana-usage-check.sh`
  (needs a read token).
- observability repo committed through `6271e8e` + this handoff.

## Onboarding playbook (per site) — all $0 while Anthropic is maxed
1. **Consolidate branches → main.** `git -C <repo> checkout main`, merge the
   `observability` (instrumentation) branch and any WIP branch, delete them
   local+remote. Then `npm run build` to confirm it still builds.
2. **Fix `netlify/functions/lib/otel.mjs`** to send the bearer header — the June-13
   instrumentation predates collector auth, so it POSTs with only `content-type` and
   the hardened collector 401s it. Parse `OTEL_EXPORTER_OTLP_HEADERS` ("k=v,k=v")
   into the fetch headers.
3. **Set Netlify env** (`netlify link --name <project>`; `netlify env:set ...`):
   - `OTEL_EXPORTER_OTLP_ENDPOINT=https://fleet-otel-collector.fly.dev`
   - `OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <ALLOY_INGEST_BEARER>`
   - `OTEL_SERVICE_NAME=<site>`   `DEPLOY_ENV=prod`
4. **Deploy** (push `main`). Confirm the site is reachable (`curl -sI https://<site> `).
5. **Verify telemetry ($0):** `fly logs -a fleet-otel-collector` — the site's
   autonomous ticks (15-min narrator / any chat hit) emit spans even when Anthropic
   401s the actual call (error span, $0 cost). Or Grafana Explore: `service.name=<site>`.

## Targets (Eric's suspects, in order)
1. **aigamma.com** — Haiku page-narrator every 15 min + per-page Sonnet/Opus chatbots.
   PR #1 instruments `chat.mjs` + `narrate-background.mjs`. Production = `main`.
   Branches to kill: `observability` (+2 telemetry), `site-quality` (+8 cosmetic WIP).
2. **worldthought.com** — ~2,200 chatbots. PR #2 (`observability` branch). Same fix.
- NOT suspects: ai-firehose.com / spokenhistory.org (raw RAG, no chatbots);
  selectsectors.com (no DNS yet).

## Decisions guessed autonomously (Eric said "guess + document, change later")
- Shipped `site-quality`'s 8 cosmetic commits to `main` along with the telemetry —
  the no-branches mandate requires consolidating it, and `vite build` passed (exit 0).
- `OTEL_SERVICE_NAME=aigamma` (the otel.mjs default).
- Verified aigamma's telemetry path by calling `recordLlm` directly with dummy token
  counts ($0), NOT by triggering a real chat — avoids any Anthropic spend in case the
  monthly limit isn't fully maxed. This is the safe per-site verification pattern.

## What's left for ERIC (needs his login / spend — do NOT do these for him)
- **Raise Anthropic monthly limit +$50** — the measured budget that turns the pipes
  back on under instrumentation. Do this LAST, after telemetry is confirmed.
- Set provider spend caps first (COST-CONTROLS Layer 0): Anthropic per-workspace,
  OpenAI prepaid balance + project budget.
- Grafana: set billing alerts; import `dashboards/llm-cost.json`; arm
  `scripts/grafana-usage-check.sh` with a read-scoped token.

## Done this session
- **aigamma.com** — branches consolidated to linear `main` (zero branches), otel.mjs
  bearer fix (`62f7613`), Netlify OTLP env set, deployed (state=ready, HTTP 200),
  telemetry path verified $0. Awaiting Eric's Anthropic limit raise to see real cost.

## Next undone step
→ Onboard **worldthought.com** (~2,200 chatbots) per the playbook, then write Eric's
  evening summary. (ai-firehose/spokenhistory = raw RAG, skip; selectsectors = no DNS.)
