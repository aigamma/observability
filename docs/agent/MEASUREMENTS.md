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
