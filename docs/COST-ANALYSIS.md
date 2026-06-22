# Where the cash is going — an LLM cost-leak analysis

**Status: framed, awaiting live data.** On 2026-06-22 Eric raised the Anthropic monthly cap
$200 → $250 (+$50 runway, plus ~$167 in credits) so real spend can flow and be measured. This is
the *lens* for that data: the ranked hypotheses for where the bleed is, the cost mechanics behind
them, and exactly what to read to confirm or kill each one. Read it as "where I think the cash is
going and how we'll prove it" — not a dashboard screenshot.

## The cost mechanics (why a few things dominate)
Spend = Σ calls × (input_tokens · price_in + output_tokens · price_out), per model. Two multipliers
swamp everything else:
- **Output costs 5× input** on every Claude tier — Opus .075/.015, Sonnet .015/.003, Haiku .004/.0008 (USD per 1K).
- **Tier dwarfs the rest:** Opus output (.075) = 5× Sonnet = ~19× Haiku. An Opus *output* token vs a Haiku *input* token is ~94×.

So spend concentrates in **(a) high-frequency operations, (b) Opus/Sonnet output, (c) large or repeated inputs.** Everything below is an instance of one of those three.

## Ranked hypotheses (the suspects)
1. **worldthought.com — the volume surface (~2,200 chatbots, `chat`).** Even at low per-bot traffic,
   2,200 bots × messages is the likeliest #1 by aggregate. Every turn pays for system prompt + history
   + any retrieved context as INPUT. **Confirm:** top-N operations by cost; `chat` cost where `service_name=worldthought`.
2. **aigamma.com — the unit-cost surface (Opus/Sonnet `chat`).** Opus output is ~19× Haiku; a handful
   of long Opus conversations can dominate a day. **Confirm:** cost-per-call by model on aigamma `chat` —
   is Opus the *default* or reserved for queries that earn it?
3. **aigamma.com — the frequency drip (`narrate`, Haiku, every 15 min).** ~2,880 calls/month
   **whether or not anyone visits** — the classic "idle but expensive." Cheap per call, but watch:
   (a) is it really Haiku? (b) does its input grow as content accumulates? **Confirm:** `narrate` cost
   over time + input-token trend; cost during zero-traffic hours (pure fixed cost shows up there).
4. **ai-firehose.com worker — RAG generation** (Anthropic, tiered by stakes; Voyage embed/rerank).
   Steady if it ingests on a schedule. **Confirm:** `classify`/generation cost vs item volume.
5. **Voyage + Pinecone — the embedding/vector sleeper.** Cheap per call, but a **re-embedding loop**
   (worldthought's `generate-graph` reads Pinecone every build) can rack up silently. **Confirm:**
   Voyage `embed` call-rate vs build cadence.

## The cache angle — the most fixable leak, and currently INVISIBLE
Anthropic prompt caching turns a repeated system prompt from full input price into ~0.1× on a hit.
With one shared persona prompt across 2,200 worldthought bots, and the same `narrate` template every
15 min, **uncached repeated input could be the single biggest, most-fixable line item.** But we can't
see it yet: the emitters (`recordLlm`) capture `input_tokens` + `output_tokens` only — **not**
`cache_read_input_tokens` / `cache_creation_input_tokens`. So cache-hit rate is unmeasured and the
cost math can be off on cached calls. **This is the #1 stack fix (below).**

## What to throttle first (once data confirms)
1. **Audit `narrate`** — confirm Haiku, confirm input isn't growing, consider 15 → 30/60 min. It's pure fixed cost; halving the cadence halves it with zero UX loss.
2. **worldthought** — find the idle-but-expensive bots and retire them; enforce per-bot rate limits; downgrade tier wherever the persona allows.
3. **aigamma** — route default `chat` to Haiku/Sonnet; reserve Opus for queries that earn it (a stakes router, like ai-firehose already does).
4. **Turn on prompt caching** for every repeated system prompt.
5. **Provider caps** — Anthropic workspace cap (done: $250), then Voyage + Pinecone caps.

## How to measure right now (no dashboard required)
The collector's debug exporter prints every `gen_ai` span/metric to `fly logs -a fleet-otel-collector`
with real token counts and the derived `gen_ai.cost.usd`. Capture a window as the services run and
tabulate by (service, model, operation) — that answers hypotheses 1–4 directly, today. The Grafana
dashboard (`dashboards/llm-cost.json`) shows the same once data lands (top-N + input/output-split
panels). Data flows from Netlify/Fly regardless of this workstation, so a re-image here doesn't
interrupt accumulation.

## Stack improvements surfaced while framing this
1. **Instrument cache tokens** (`cache_read` / `cache_creation`) in `recordLlm`, plus a cache-hit-rate panel — without it the biggest lever is blind. *(highest value)*
2. **Per-bot attribution vs cardinality.** Finding the idle-expensive worldthought tail wants per-`chatbot_id` cost — but 2,200 IDs × models as labels would explode billable series (the cardinality guard rightly drops IDs). Resolve with sampled exemplars or a periodic top-N rollup, **not** a label per bot. This tension is the central design problem of fleet cost-attribution.
3. **A spend-velocity alert** (`rate(gen_ai_cost_usd_total[1h])`) to catch a runaway in minutes, not after $50 has accrued (the review's alert gap).
4. **Distinct operation names** for every scheduled job (`narrate` already is) so fixed-cost drips stay isolable from user-driven spend.

---
*Next session: capture a `fly logs` window once `narrate` has fired a few times and chatbots have seen
traffic, fill in real (service, model, operation) cost numbers under each hypothesis, and confirm or
kill the ranking. Then act on "What to throttle first."*
