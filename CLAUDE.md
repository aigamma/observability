# Observability spine — agent onboarding

You are working on the fleet OpenTelemetry **cost**-observability stack. This file is auto-loaded
every session in this repo. The mission is urgent and specific: **find and stop the LLM-API cash
leak** that forced Eric to take his sites offline — attribute spend by service / model / operation
so he can throttle or retire whatever bleeds.

## Come up to speed immediately — do this first, every session
1. **Read the most recent commits.** They carry the live state and the half-finished ideas that
   aren't written up yet: `git -C D:\observability log --oneline -25` (and the site repos too).
2. **Read the harness docs**, newest-truth first:
   - `docs/agent/SESSION-STATE.md` — durable snapshot: done / deferred / every repo's HEAD.
   - `docs/COST-ANALYSIS.md` — **where the cash is going** (the headline deliverable).
   - `docs/agent/FOUNDATION-REVIEW.md` — the multi-agent review + the co-strategy backlog.
   - `docs/agent/HANDOFF.md` + `docs/agent/CHANGELOG.md` — running log + per-site onboarding recipes.

## Working rules (Eric, explicit — honor every session)
- **Commit liberally and verbosely — for both code AND docs.** A verbose message is the cheapest
  durability there is; the next agent learns what happened by reading commits.
- **Push less often (batch ~10 commits)** to spare build credits — but **NEVER walk away or pause
  anything without pushing.** Unpushed finished work on this machine is one re-image from gone.
- **One linear history on the default branch. No branches, no PRs, ever** (see global CLAUDE.md).
- **Spend discipline:** do not run project code that hits a paid API (Anthropic/Voyage/Pinecone) to
  "generate data." The leak we measure must be the ORGANIC service traffic, never synthetic spend.
- After pushing, confirm `HEAD==origin`. Secrets live only in Fly/Netlify env, never in git.

## The fleet (suspects in **bold**)
- **aigamma.com** — `chat` (Haiku/Sonnet/Opus chatbots) + `narrate` (Haiku summary every 15 min). Live.
- **worldthought.com** — `chat` across ~2,200 chatbots. Live. The volume surface.
- ai-firehose.com — worker RAG: `classify` etc. (Anthropic, tiered by stakes) + Voyage embed/rerank. Live.
- spokenhistory.org — Voyage embed+rerank only (cheap). Instrumented but DORMANT until its Netlify OTEL env is set.
- Collector — Grafana Alloy on Fly (`fleet-otel-collector`): bearer-authed, redacts prompt/PII (spans+logs), → Grafana Cloud Pro (US-East/VA).

## How to measure without a dashboard
The collector's debug exporter prints every `gen_ai` span/metric to `fly logs -a fleet-otel-collector`
with real token counts and the derived `gen_ai.cost.usd`. That is the live oracle — capture a window
as the services run and tabulate by (service, model, operation). Data flows from Netlify/Fly
independent of this workstation, so a re-image here never interrupts it.
