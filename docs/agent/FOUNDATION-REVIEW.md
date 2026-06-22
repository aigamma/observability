# Foundation Review — 2026-06-22 (partial)

A multi-agent ("ultracode") review of the fleet-observability foundation, read-only, no
branches. **Partial run:** a 25-agent fan-out tripped Anthropic's *server-side* rate limiter
(not Eric's quota), so the **collector**, **security**, and **cost-model** reviews and the
final synthesis did not complete. The **docs** dimension (plus part of instrumentation)
finished, yielding **7 findings, each adversarially re-confirmed against the actual files**.
Raw, verbatim findings: [`foundation-review-findings.json`](foundation-review-findings.json).

## Verified findings
1. **[FIXED] README sold a "free tier / $0" story while the account is Grafana Cloud Pro.**
   This inverted the core premise: the ingest bearer-auth and cardinality guard are genuine
   *wallet locks only on Pro* (free tier hard-blocks at the limit — no overage — making them
   moot). Fixed README lines 6 / 33 / 44.
2. **[TO FIX] README "Verify end to end" command omits the bearer token.** Run as written,
   ingest auth (now enforced) 401s every POST and `send-synthetic.sh` exits non-zero — so the
   documented happy-path "proves the pipeline + redaction" actually proves a *rejection*. Fix:
   prefix `ALLOY_INGEST_BEARER=...` (as COST-CONTROLS.md:99 and the script's usage line do).
3. **[TO FIX] ONBOARDING lists a live Faro RUM browser URL on port 12347**, which `fly.toml`
   and the same doc (line ~196) say is closed. Fix: caption it deferred-until-RUM-onboarding.
4.–7. Additional instrumentation-consistency and doc-rot items — see the raw JSON.

## Technical review — completed via one focused agent (collector / security / cost-model)
- **COST-MODEL P1 [FIXED] — token & calls dashboard panels were dead.** Emitters set
  `unit:'token'`/`'call'`, so OTLP→Prometheus appended the unit → `gen_ai_usage_input_tokens_token_total`,
  which the dashboard's `..._tokens_total` never matched (cost panels survived by a dedup coincidence).
  Fixed: dropped the unit on the token/call counters in **all four** emitters. ⚠️ aigamma + worldthought
  must **redeploy** for it to take effect on the live series.
- **COST-MODEL P2 [FIXED] — synthetic canary invisible to the dashboard:** its metric datapoint lacked
  `deployment.environment` (which every panel filters on). Added it.
- **SECURITY P1 [DEFERRED] — redaction is trace-only.** No `log_statements` in `govern`, so prompt/PII in
  LOGS (incl. the Faro→Loki bridge) leaves un-redacted, and the `detailed` debug exporter dumps those
  bodies to `fly logs`. Fix: add a `log_statements` block mirroring the trace deletes; drop debug verbosity.
- **COLLECTOR P1 [DEFERRED] — no egress durability:** the otlphttp exporter has no `sending_queue` +
  `file_storage`, so a Cloud outage or machine-suspend silently drops telemetry.
- **SECURITY P1 [DEFERRED] — no ingest rate-limiting:** bearer gates *who*, nothing gates *how much* — a
  compromised/shared-bearer holder can flood paid ingest. Add a request-size / rate cap.
- **SECURITY P2 [DEFERRED] — one shared ingest bearer fleet-wide:** no per-sender identity (service.name is
  self-asserted), rotation needs a coordinated redeploy. Move to per-site bearers.
- **COLLECTOR P2 [DEFERRED] — memory_limiter 180+40MiB on a 256MB box** is tight (OOM risk); remove the
  debug exporter + `--stability.level=experimental` post-verification.
- **Solid, no defects:** pipeline topology, tail-sampling, bearer-on-both-receivers, the cardinality
  key-regex, the closed Faro port.

These DEFERRED items are the co-strategy backlog: redaction-for-logs + egress durability + ingest
rate-limiting + per-site identity are the hardening that turns this from "works for me" into "safe at fleet
scale." Re-run any future review as ≤6 sequential agents (the 25-way fan-out rate-limited itself).

## For co-strategy (when Eric's back)
- The recurring **doc-rot** pattern (free→Pro, no-auth→bearer, Faro-open→closed) shows the
  prose lags the fast-moving config. Worth a small "docs assert against reality" check (grep
  doc claims vs. the live `config.alloy` / `fly.toml`) so the foundation stays honest at scale.
- Finish the collector/security/cost review, then the strategic hardening the security
  dimension was going to surface: **ingest-token rotation, per-site identity (vs one shared
  bearer), and ingest rate-limiting**.
