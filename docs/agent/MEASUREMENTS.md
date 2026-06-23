# Measurement log — live telemetry captures

Append-only log of what the collector actually showed, read from `fly logs -a fleet-otel-collector`
(the debug exporter prints every gen_ai signal with real tokens + derived cost). Newest at top.
Eric reopened the Anthropic spigot ~2026-06-22 23:00 UTC; organic spend accumulates as services run
(`narrate` every 15 min; chatbots on traffic; RAG on ingest/query).

## Capture 1 — 2026-06-22 ~23:05 UTC (120 s window)
**Pipeline healthy; no ORGANIC traffic yet — only synthetic/verify signals.**
- Services: `synthetic-verify`, `aigamma-verify`, `ai-firehose-verify`, `worldthought-verify`, `cardinality-test` — all canaries/tests. No production `aigamma` / `worldthought` / `ai-firehose-worker`.
- Operations: `verify` (9) + `chat` (3, all from `synthetic-verify`). Models seen: haiku, sonnet, opus, voyage-3 — all synthetic.
- No real `narrate`, chatbot `chat`, or RAG `embed`/`classify`. Expected this soon after the spigot opened.
- ✅ End-to-end confirmed: signals received → redacted → exported. **Re-capture ~23:30 UTC for organic spend.**

## Headline insight (from the code, not the logs): cache cost is UNMEASURED on the #1 suspects
- aigamma `chat.mjs` and worldthought `chat.mjs` / `connection-chat.mjs` use Anthropic **prompt caching**
  (`cache_control: { type: 'ephemeral' }` on system prefixes + tool blocks; aigamma even comments the breakpoints).
- But `recordLlm` is fed only `usage.input_tokens` (`aigamma chat.mjs:655`) — **`cache_read_input_tokens` (billed 0.1×)
  and `cache_creation_input_tokens` (billed 1.25×) are dropped on the floor.**
- **Consequence:** the dashboard *undercounts the real chatbot bill* — the cached portion is usually the bulk of the
  input, so the most expensive/most-reused calls look cheapest — and cache efficiency (hit rate, thrash) is invisible.
  The firehose worker (`anthropic.mjs`) and `narrate` don't cache, so they're already accurate.
- **Why it matters:** when the dashboard total < the Anthropic invoice, the gap is mostly this. Fixing it reconciles
  the two and turns "is the cache even working?" into a number.
- **Fix (implementing now):** capture both cache fields in `recordLlm`, fold them into `costUsd` (write 1.25× / read
  0.1× of base input price), emit `cache_read` / `cache_creation` counters, and add a cache panel.

## 2026-06-22 evening — what I built (Eric on a bike ride)
- **Cache fix DONE + deployed:** aigamma (`e8ccf4e`) + worldthought (`65ef01f`) chat now capture
  `cache_read`/`cache_creation` from `message_start`, price them in `costUsd` (write 1.25× / read 0.1×),
  and emit `cache_read_tokens` / `cache_creation_tokens` counters. Cost math unit-tested (PASS).
- **Dashboard:** added panels 7 (cache tokens/sec: read vs creation vs uncached input) + 8 (cache
  hit-ratio stat) to `dashboards/llm-cost.json`.
- **NEW blind spot found + fixed:** worldthought `connection-chat.mjs` — the /connections Sonnet
  synthesis modal (64k output, doubled RAG) — raw-forwarded its SSE and recorded **nothing**: a fully
  invisible Sonnet spend path. Instrumented additively (`b260458`); now emits `operation=connection-chat`.

## Capture 2 — 2026-06-22 ~23:30 UTC (150 s)
Still **no organic traffic** — only the synthetic/verify canaries again; `narrate` count **0**; no cache
tokens yet (deploys still propagating + no chatbot users at this hour). Pipeline healthy; the bleed
simply isn't flowing this minute (Eric expected this — "maybe we'd have to wait for a RAG cycle").
**Watch item:** `narrate` (the 15-min cron) reads 0 across two windows — confirm it's actually firing
once organic data appears (cold cron vs. buffer scroll). Re-capture later for organic spend.

## Instrumentation coverage audit — 2026-06-22 evening
Grep of every Anthropic/Voyage call site vs. `recordLlm` across the active repos:
- ✅ **All live Anthropic (the expensive paths) are instrumented:** aigamma `chat` + `narrate`,
  worldthought `chat` + `connection-chat` (just fixed), ai-firehose worker `anthropic`. No invisible
  Claude spend remains.
- ⚠️ **Query-time Voyage embeds uninstrumented** in worldthought `chat.mjs` + `connection-chat.mjs`
  (RAG retrieval). Negligible (~$0.000006/query) — documented, not worth wiring.
- ⚠️ **RAG scripts** (`aigamma scripts/rag/reembed.mjs`, `worldthought scripts/rag/ingest.mjs`) embed the
  whole corpus via Voyage with no telemetry. Manual/offline, but this is the "re-embedding loop" cost
  vector — instrument if they ever move to a schedule.
- **Net: the dashboard now captures all live Claude spend; the only gaps are cheap or manual.**

## `narrate` trigger finding — 2026-06-22
`narrate-background.mjs` is instrumented (operation `narrate`) but reads **0** across all captures.
Cause established: it is **not a Netlify scheduled function** — no `schedule` in `netlify.toml`, no
`export const config = { schedule }`. Its "every 15 min" cadence is driven by an **external** trigger
(separate cron / GitHub Action / manual). So a 0 reading most likely means that trigger is currently
OFF (consistent with Eric having taken things down): the suspected 15-min Haiku drip is **dormant right
now, not leaking**. **Action:** when expecting the drip, confirm the external trigger is live; once it
is, `narrate` cost appears and the fixed-cost hypothesis (hypothesis #3 in COST-ANALYSIS) can be sized.

## Static cost grounding — prompt sizes (no organic traffic needed)
Measured the cacheable system-prompt material via `wc -c` (bytes ≈ tokens/4):
- aigamma narrator `_persona.mjs` alone = 14 KB ≈ **3,500 tokens**; the full cached prefix adds site-nav +
  site-index, so aigamma's per-call cached prefix is **several thousand tokens**.
- worldthought: ~1.6 MB of prompt files across its ~2,200 rooms (≈ 740 B / ~185 tokens per persona);
  per-call cached prefix ≈ shared head (~385 tokens) + one room persona — **small per call, huge in aggregate**.
- **Implication:** caching is worth real money both ways — aigamma via large per-call prefixes, worldthought
  via volume. The hit-vs-thrash distinction (now instrumented + alerted) is material: a cache that THRASHES
  bills 1.25× these tokens per call instead of 0.1× on a hit — **~12× worse**. That is the leak to watch first
  once traffic flows; the new cache panel + `LlmPromptCacheThrash` alert will surface it.
