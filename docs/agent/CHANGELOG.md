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

### In progress
- Onboarding aigamma.com (Eric's prime leak suspect): consolidate branches → main,
  fix the otel.mjs bearer header, set Netlify env, deploy, verify. All $0 (Anthropic
  maxed). worldthought.com next, same playbook.
