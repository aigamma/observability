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

## NOT covered (rate-limited — needs a re-run)
Collector correctness/robustness, security hardening, cost-model + dashboard cross-checks,
and the cross-cutting synthesis. **Re-run as ≤6 sequential/pipelined dimension agents, not 25
parallel**, so the back half isn't throttled. (Lesson logged: cap review fan-out concurrency.)

## For co-strategy (when Eric's back)
- The recurring **doc-rot** pattern (free→Pro, no-auth→bearer, Faro-open→closed) shows the
  prose lags the fast-moving config. Worth a small "docs assert against reality" check (grep
  doc claims vs. the live `config.alloy` / `fly.toml`) so the foundation stays honest at scale.
- Finish the collector/security/cost review, then the strategic hardening the security
  dimension was going to surface: **ingest-token rotation, per-site identity (vs one shared
  bearer), and ingest rate-limiting**.
