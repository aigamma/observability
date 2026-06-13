# Onboarding a Site

Every recipe below obeys three rules:

1. **Fail-open and env-gated.** With no `OTEL_EXPORTER_OTLP_ENDPOINT` set, the
   instrumentation does nothing. It ships to production dormant and activates
   only once the endpoint env var is present. Telemetry must never break the app.
2. **Standard conventions.** LLM calls emit `gen_ai.*` attributes and the
   `gen_ai.client.token.usage` metric automatically via OpenLLMetry. Do not
   invent metric names.
3. **No content off-box.** Prompt/completion text is disabled at the source and
   redacted again at the collector. Token counts and cost are what travel.

The collector endpoints (replace host once the Fly app name is final):

| Signal | URL |
|---|---|
| OTLP/HTTP (backends) | `https://fleet-otel-collector.fly.dev` (SDK appends `/v1/...`) |
| Faro RUM (browsers) | `https://fleet-otel-collector.fly.dev:12347/collect` |

Set per service: `OTEL_SERVICE_NAME`, `DEPLOY_ENV` (`prod`/`dev`), and
`OTEL_EXPORTER_OTLP_ENDPOINT` (the OTLP/HTTP URL above).

---

## Node serverless (Netlify functions)

`npm i @traceloop/node-server-sdk @opentelemetry/api`

Shared helper, committed once per repo as `netlify/functions/lib/otel.mjs`:

```js
import * as traceloop from "@traceloop/node-server-sdk";

const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
let started = false;

export function startTelemetry({ appName, serverless = true } = {}) {
  if (started || !endpoint) return;          // fail-open: no endpoint -> no-op
  traceloop.initialize({
    appName: appName || process.env.OTEL_SERVICE_NAME || "unknown",
    baseUrl: endpoint,                        // http(s) prefix => OTLP/HTTP
    disableBatch: serverless,                 // immediate export before freeze
    traceContent: false,                      // never capture prompt/response text
  });
  started = true;
}

// Wrap a Netlify handler so telemetry starts and spans flush before return.
export function withTelemetry(handler, opts = {}) {
  return async (...args) => {
    startTelemetry(opts);
    try { return await handler(...args); }
    finally { try { await traceloop.forceFlush?.(); } catch {} }
  };
}
```

Per function, the only change is the wrap:

```js
import { withTelemetry } from "./lib/otel.mjs";
export const handler = withTelemetry(async (event) => {
  // ... existing handler. OpenAI/Anthropic calls auto-emit gen_ai.* spans.
}, { appName: "aigamma-chat" });
```

OpenLLMetry auto-instruments the OpenAI, Anthropic, Pinecone, and LangChain
clients it finds, so no per-call edits are needed for token capture.

---

## Node long-running worker (Fly)

Same package and helper, but batch (not serverless) and start once at boot,
before the LLM clients are imported:

```js
import { startTelemetry } from "./lib/otel.mjs";
startTelemetry({ appName: "ai-firehose-worker", serverless: false });
```

Where the code already reads a response, also feed the cost counter so spend is a
first-class metric (the price table is the single source of truth for $/1k):

```js
import { metrics } from "@opentelemetry/api";
const costCounter = metrics.getMeter("llm-cost")
  .createCounter("gen_ai.cost.usd", { unit: "usd" });
const PRICES = { // [in, out] USD per 1k tokens
  "claude-haiku-4-5": [0.0008, 0.004], "claude-opus-4-8": [0.015, 0.075],
  "gpt-4o": [0.0025, 0.01], "voyage-3": [0.00006, 0],
};
export function recordLlmCost({ model, inputTokens = 0, outputTokens = 0, operation = "chat" }) {
  const [pin, pout] = PRICES[model] || [0, 0];
  costCounter.add((inputTokens / 1000) * pin + (outputTokens / 1000) * pout, {
    "gen_ai.request.model": model, "gen_ai.operation.name": operation,
    "service.name": process.env.OTEL_SERVICE_NAME || "unknown",
    "deployment.environment": process.env.DEPLOY_ENV || "prod",
  });
}
// after a call:  recordLlmCost({ model, inputTokens: resp.usage.input_tokens, outputTokens: resp.usage.output_tokens, operation: "classify" })
```

Cost can also be derived entirely in Grafana from `gen_ai.client.token.usage`;
the in-app counter is the cleaner, lower-cardinality path when usage is in hand.

---

## Browser / React (Grafana Faro RUM)

`npm i @grafana/faro-web-sdk @grafana/faro-web-tracing`

In the SPA entry (`src/main.jsx`), before rendering:

```js
import { initializeFaro, getWebInstrumentations } from "@grafana/faro-web-sdk";
import { TracingInstrumentation } from "@grafana/faro-web-tracing";

const url = import.meta.env.VITE_FARO_URL;   // fail-open: unset => skip
if (url) {
  initializeFaro({
    url,
    app: { name: "ai-firehose", version: import.meta.env.VITE_APP_VERSION || "dev",
           environment: import.meta.env.MODE },
    instrumentations: [...getWebInstrumentations(), new TracingInstrumentation()],
  });
}
```

`TracingInstrumentation` injects `traceparent` into every fetch/XHR, so a browser
span links to the backend span of the same request: one trace, click to LLM call.

---

## Rust (Fly, axum/tower)

`Cargo.toml`:

```toml
opentelemetry = "0.28"
opentelemetry_sdk = { version = "0.28", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.28", features = ["http-proto", "reqwest-client"] }
tracing = "0.1"
tracing-opentelemetry = "0.29"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
```

Init (fail-open on the endpoint env), exporting OTLP/HTTP through Fly TLS:

```rust
pub fn init_telemetry(service: &str) -> Option<opentelemetry_sdk::trace::SdkTracerProvider> {
    let endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT").ok()?; // None => no-op
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_http().with_endpoint(format!("{endpoint}/v1/traces")).build().ok()?;
    let provider = opentelemetry_sdk::trace::SdkTracerProvider::builder()
        .with_batch_exporter(exporter)
        .with_resource(opentelemetry_sdk::Resource::builder().with_service_name(service.to_string()).build())
        .build();
    opentelemetry::global::set_tracer_provider(provider.clone());
    Some(provider)
}
```

Bridge `tracing` to OTel with `tracing_opentelemetry::layer()`, add
`tower_http::trace::TraceLayer` to the router, and `#[tracing::instrument]` the
handlers. RED, SQLx query spans, and runtime metrics follow.

---

## Supabase Deno edge functions

Use the OTLP/HTTP exporter from the OTel JS packages via `npm:` specifiers, gated
on `OTEL_EXPORTER_OTLP_ENDPOINT`, and span the embedding + pgvector queries
(`rag-search`, `rag-ingest`). Same conventions as Node.

---

## Python (e.g. a Whisper-backed pipeline)

`pip install traceloop-sdk` then `Traceloop.init(app_name=..., api_endpoint=OTEL_ENDPOINT, disable_batch=True)`,
gated on the endpoint env. Auto-instruments the OpenAI/Anthropic clients.

---

## Hardening: ingest auth (before the collector runs continuously)

Add a server-side bearer authenticator to the OTLP and Faro receivers in
`alloy/config.alloy`, set `ALLOY_INGEST_BEARER` as a Fly secret, and have each
service send `Authorization: Bearer <token>` (OTel: `OTEL_EXPORTER_OTLP_HEADERS`;
Faro: the `apiKey`/headers option). Until then, verify with the machine stopped
when idle so there is no standing open endpoint.
