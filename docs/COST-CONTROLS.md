# Cost Controls — the layered defense, and the checker *against* Grafana

This stack exists to find and stop runaway LLM-API spend. This doc is the set of
guardrails so that (a) the diagnosis doesn't itself create new leaks, and (b)
Grafana — which watches everything else — is itself watched.

> Read this first if you're catching up: the collector is live and verified, but
> **none of these guardrails replace the provider spend caps in Layer 0.** Those
> are the only thing that hard-stops money. Do them first.

## The mental model: money can only leak in two places

1. **The LLM providers** — Anthropic, OpenAI, Voyage, Pinecone. This is the real
   cash leak: metered inference, billed per token. The collector and Grafana only
   *observe* it; they never spend it.
2. **Grafana Cloud Pro** — usage-based. The watcher itself can bill you if its
   ingest is flooded or your apps emit high-cardinality metrics.

Every layer below caps one of those two. Layers are ordered outermost (hardest
stop, least precise) to innermost (most precise, least forcing).

---

## Layer 0 — Provider spend caps (the seatbelt; do this first)

Hard ceilings that stop money regardless of any bug in your code or this stack.

### Anthropic (Claude)
Per-**workspace** spend limits, evaluated on every request alongside the org limit.
1. Console → **Workspaces** → click the workspace → **Limits** tab.
2. Click the pencil next to each model tier and set a monthly spend limit.
3. **Add notification** to get an email when spend crosses a threshold.
- Put each app/site in its **own workspace** → the cap is per-app *and* you get
  per-app attribution for free in Usage/Cost Reports.
- Docs: [Workspaces](https://support.anthropic.com/en/articles/9796807-creating-and-managing-workspaces) ·
  [Cost & Usage Reporting](https://support.anthropic.com/en/articles/9534590-cost-and-usage-reporting-in-console)

### OpenAI
OpenAI API billing is **prepaid**, so your hard ceiling is simply the credit
balance you load — it cannot overspend that. On top of that:
1. Platform → **Settings → Limits** (per project): set **Monthly budget**,
   **Notification threshold**, and **Model usage** restrictions.
2. Note: the project "monthly budget" is a **soft** alert (requests keep flowing);
   the **org-level usage limit + prepaid balance** is the hard stop.
- Keep the loaded balance modest and auto-recharge **off** until the leak is found.
- Docs: [Usage limits](https://platform.openai.com/settings/organization/limits) ·
  [Why am I hitting my usage limit](https://help.openai.com/en/articles/6614457-why-am-i-getting-an-error-message-stating-that-ive-reached-my-usage-limit)

### Voyage / Pinecone
Set plan/usage caps where the dashboard allows; otherwise rely on Layer 2 + alerts.

---

## Layer 1 — One API key per site/workflow

- Separate keys → your provider usage dashboard attributes spend **per app**,
  instantly, for free. One shared key only shows model-level totals and forces you
  to lean on the spine to attribute.
- Contains blast radius: a leaked or abused key exposes one app, not the fleet.

## Layer 2 — App-level rate limits (per site)

- Per-user / per-IP / per-session request quotas on each chatbot.
- A **max-iterations cap** on every agent loop. (The "hit a limit, proceed, hit it
  again instantly" pattern is almost always a loop with no ceiling, or a scheduled
  job firing too often — find it in the by-operation panel.)
- Cache aggressively: prompt caching, embedding cache, and **never re-embed
  unchanged content** (a classic silent re-embedding loop is a top leak).

## Layer 3 — The spine (Grafana): observe, attribute, alert

- `dashboards/llm-cost.json` breaks spend down by service / model / operation, with
  the input-vs-output token split (output costs several times more).
- `alerts/llm-budget.rules.yaml` warns *before* you hit a cap, naming the driver.
- This is what tells you **which knob above to turn, and by how much** — with data,
  not vibes.

---

## Layer 4 — The checker *against* Grafana (watch the watcher)

Grafana watches your apps; on a paid plan it needs its own independent checks, for
two distinct failure modes: **it costs too much**, or **it silently stops capturing
data** (so a quiet dashboard reads as "all clear" when it actually means "broken").

### 4a — Grafana Cloud billing alerts (cost; in-portal)
Cloud Portal → **Cost Management / Billing** → set usage + billing alerts on metrics
active series, logs GB, and traces GB. On the **free** tier Grafana hard-blocks at
the limit (no overage bill); on **Pro** it warns but keeps accruing — so on Pro
these alerts are the difference between "warned early" and "surprised by an invoice."

### 4b — Independent usage watch (cost; outside Grafana)
`scripts/grafana-usage-check.sh` queries Grafana Cloud's own usage metrics from
**outside** Grafana and warns if active series or ingest spikes — so a problem with
Grafana can't hide itself inside Grafana. It needs a **read-scoped** access policy
token (see the script header). Arm it in the morning, then schedule it.

### 4c — Synthetic canary (correctness; independent)
`scripts/send-synthetic.sh` (with `ALLOY_INGEST_BEARER` set) proves the whole
pipeline still ingests → redacts → exports, on demand, and exits non-zero if any
push isn't accepted. Schedule it so "no data on the dashboard" can never silently
mean "the pipeline broke" instead of "nothing is happening." It also re-proves
redaction every run (the secret prompt must not survive).

### 4d — Cardinality discipline (cost; built into the collector)
Token/cost metrics stay keyed only by **service / model / operation / environment**.
Prompt text, user ids, session ids, and request ids must **never** become metric
labels — each unique value is a new billable series. The collector already strips
prompt/completion text; a metric-attribute denylist for high-cardinality ids is the
next guardrail in `alloy/config.alloy` (so a buggy site can't explode your series
count = your Pro bill).

---

## Quick morning checklist

- [ ] **Layer 0 first** — set Anthropic per-workspace spend limits + OpenAI project
      budgets; keep OpenAI prepaid balance modest, auto-recharge off.
- [ ] Skim each provider's **Usage** dashboard for the last 30 days — where did the
      money *already* go? (Fastest answer to "where's the leak," no Grafana needed.)
- [ ] Set **Grafana Cloud billing alerts** (4a).
- [ ] Import `dashboards/llm-cost.json` (Dashboards → Import → paste JSON).
- [ ] Confirm the synthetic data is visible: Grafana → **Explore** →
      `service.name="synthetic-verify"`.
- [ ] Mint a **read-scoped** Grafana token and arm `scripts/grafana-usage-check.sh`.
- [ ] Re-arm sites one at a time, behind Layer 1/2, watching the dashboard between
      each — never all at once.
