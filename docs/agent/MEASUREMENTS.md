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
