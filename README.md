# Fleet Observability

One centralized OpenTelemetry spine for the whole fleet: every site ships
**metrics + traces + logs + browser RUM** to a self-hosted [Grafana Alloy]
collector, which redacts, samples, and forwards a single OTLP/HTTP egress to
**Grafana Cloud** (free tier). The headline surface is **LLM cost and token
observability**, so a $150 OpenAI surprise becomes a dashboard and an alert that
warns days ahead, broken out by service, model, and operation.

This repo is the spine and the runbook. The per-site instrumentation lives in
each site's own repo, added with the copy-paste recipes in
[`docs/ONBOARDING.md`](docs/ONBOARDING.md).

## Why this exists

- **See where tokens leak.** Spend per service / model / operation, the
  input-vs-output split (output tokens cost several times more), top-N most
  expensive operations, and cache-hit savings.
- **Never get surprised by a bill again.** A budget alert fires when projected
  monthly spend crosses a soft threshold, naming the culprit, before the cap.
- **Decide what to throttle or retire with data,** not vibes: a per-chatbot
  request-rate + cost + last-used panel separates "idle but expensive" from
  "rarely used but high signal."
- **Learn the craft by running it.** The design models correct practice on
  purpose (below), because the point is to internalize it.

## Architecture

```
  Browsers (React SPAs) ──Faro──┐
  Node serverless (Netlify fns) ─┤
  Node worker (Fly)            ──┤   OTLP        ┌──────────────────┐
  Supabase Deno edge functions ──┼──(4317/4318)─▶│  Grafana Alloy   │──▶ Grafana Cloud (free)
  Rust services (Fly, Netlify) ──┤   + Faro      │  on a 256MB Fly  │     Mimir  metrics (13mo)
  Local LM Studio / Ollama lab ──┘   (12347)     │  machine         │     Loki   logs    (30d)
                                                 │  redact·sample·  │     Tempo  traces  (30d)
                                                 │  batch           │     Frontend Obs (RUM)
                                                 └──────────────────┘     Grafana dashboards
```

The spine is the one piece worth self-hosting: it is the most instructive and
most transferable part of OpenTelemetry, and it is where governance lives
(redaction, sampling, environment tagging) for the whole fleet at once. Storage
and dashboards are managed (Grafana Cloud free tier: 10k series, 50GB logs, 50GB
traces, 13-month metric retention, $0), so there is no database to operate.

## The teaching frame (what the design models on purpose)

- **Semantic conventions over ad-hoc names.** LLM calls emit the standard
  `gen_ai.*` attributes and the `gen_ai.client.token.usage` metric, so token and
  model data are portable across backends instead of bespoke per app.
- **Three pillars + RUM, and when each earns its place.** Metrics for cheap
  aggregates and alerts; traces for per-request causality (where latency and
  cost are born); logs for detail; RUM for the real user's experience. Faro
  injects `traceparent` so a browser span links to the backend span it caused.
- **RED for services** (Rate, Errors, Duration), **cost as a fourth golden
  signal** for LLM services, **USE** for the Rust services and the worker.
- **Cardinality discipline.** Token counts are metrics keyed only by service /
  model / operation / environment. Prompt text, user ids, and request ids never
  become metric labels. This is the privacy lesson and the cost lesson at once.
- **Redaction at the spine, not on trust.** The collector deletes prompt and
  completion text before anything is exported (see `alloy/config.alloy`), so no
  app can leak it by accident.
- **Exemplars** wire a metric spike to an example trace, so "expensive minute"
  jumps straight to the offending call.

## Deploy the spine

Prereqs: `flyctl` authenticated. From the repo root:

```bash
fly apps create fleet-otel-collector      # one time
fly deploy                                 # builds alloy/Dockerfile via Fly's remote builder
```

The collector boots immediately. Until the Grafana Cloud secrets exist, egress
is a local no-op (set in `fly.toml`) and the **debug exporter** prints every
signal to `fly logs`, which is how Wave 0 is verified without an account.

When the Grafana Cloud account is ready (Connections > OTLP):

```bash
fly secrets set \
  GRAFANA_CLOUD_OTLP_ENDPOINT="https://otlp-gateway-prod-<zone>.grafana.net/otlp" \
  GRAFANA_CLOUD_INSTANCE_ID="<numeric instance id>" \
  GRAFANA_CLOUD_API_TOKEN="<cloud access policy token>"
fly deploy
```

That is the only change needed to light up real storage and dashboards.

## Verify end to end

```bash
COLLECTOR_URL=https://fleet-otel-collector.fly.dev scripts/send-synthetic.sh
fly logs -a fleet-otel-collector
```

The synthetic trace carries a fake secret prompt. In the logs you should see the
span `chat anthropic` with `gen_ai.usage.*` present and
`gen_ai.prompt.0.content` **absent**, which proves the pipeline and the
redaction in one shot.

## Security posture

- Secrets live only as Fly secrets, never in this repo (`.gitignore` enforces).
- **Incoming-ingest auth is a hardening step, not yet enforced.** During first
  bring-up the machine is stopped when not actively being verified, so there is
  no standing open endpoint. Before the collector runs continuously, add a
  bearer-token authenticator to the receivers and set `ALLOY_INGEST_BEARER`
  (see `docs/ONBOARDING.md`).

## Onboarding a site

All app instrumentation is **fail-open and env-gated**: with no OTLP endpoint
set, it is a complete no-op, so it ships to production dormant and activates only
when the endpoint env var is present. Recipes per runtime (Node serverless, Node
worker, Browser/Faro, Rust, Supabase/Deno, Python) are in
[`docs/ONBOARDING.md`](docs/ONBOARDING.md).

## Fleet status

| Site | Runtime | State |
|---|---|---|
| (spine) `fleet-otel-collector` | Grafana Alloy on Fly | Built; Cloud egress pending account |
| ai-firehose.com | Node worker + Netlify fn + React | Pilot (Wave 1) |
| aigamma.com (+ about) | Netlify fns + Supabase + React | Wave 2 |
| worldthought.com | Netlify fns + React | Wave 3 |
| learnrust.ai | Rust on Fly | Wave 4 |
| selectsectors.com | Rust + Netlify | Wave 4 |
| spokenhistory.org | Netlify fns + RAG + MCP | Wave 5 (cloned) |
| leaderlogic.org / robotlogic.org | unknown | Blocked: no repo located |

[Grafana Alloy]: https://grafana.com/docs/alloy/latest/
