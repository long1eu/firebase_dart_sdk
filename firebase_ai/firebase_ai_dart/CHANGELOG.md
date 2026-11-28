## 0.1.0

- Both backends: the Gemini Developer API, and Agent Platform with a location.
- `generateContent`, `generateContentStream` (REST and server-sent events, read through a bounded decoder) and
  `countTokens`.
- `ChatSession`: history, unary and streaming sends, and one history rule for both.
- Multimodal input: text, inline data (bytes) and file URIs.
- Manual function calling: declarations, function-call parts in responses, function-response parts in requests.
- Structured output: `responseMimeType`, with `responseSchema` (`Schema`) or `responseJsonSchema` (`JsonSchema`).
- Safety settings and ratings; thinking configuration and thought parts; the Google Search, URL context, code
  execution and Google Maps tools, passed through; image and audio output request fields passed through.
- App Check (session and limited-use) and Firebase Auth headers.
- An error model where every non-2xx answer is an exception carrying its status (`FirebaseAIException`).
- A per-call `timeout` and `abortTrigger`.
- The VM (macOS, Windows, Linux) and the web (dart2js, dart2wasm).
- Seven example programs, the guide `docs/guides/ai_logic.md`, the decisions and parity documents, the web example
  `examples/ai_web` and a production verification kit.
