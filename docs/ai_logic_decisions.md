# AI Logic decisions

The decisions behind `firebase_ai_dart` (`firebase_ai/firebase_ai_dart`): where the package differs from the official
SDKs and FlutterFire, why, which alternatives were considered and rejected, and which test pins each decision.
[remote_config_decisions.md](remote_config_decisions.md) is the model of this document. The comparison with the other
SDKs, feature by feature, is in [ai_logic_parity.md](ai_logic_parity.md); the guide is
[guides/ai_logic.md](guides/ai_logic.md).

The rule behind every row: protocol, request shapes and response shapes follow the Firebase JavaScript SDK; the Dart API
follows FlutterFire; token handling follows the shared App Check seam of `firebase_app_dart` and
`_firebase_transport_dart`. A departure needs a written reason.

The first part lists the departures from upstream, numbered as in the specification (rows 10 and 16 belong to phase 2
and are in the second part). The second part lists the decisions that bind phase 2 (0.2.0). The third part lists the
alternatives that were considered for the rest of the design.

Every row ends with a status line:

- **designed**: the behaviour is specified and the pinning test is not written yet (tests are written after the
  closing review);
- **built**: the code does this, and the test named under "Pinned by" passes.

All rows are **designed** when this document is written; the lead updates the status lines when the tests are run.

Path shorthand for upstream code:

| Short | Meaning |
|---|---|
| `JS/` | `packages/ai/src/` of firebase-js-sdk 3.1.0 (`a086865`) |
| `AND/` | `ai-logic/firebase-ai/src/main/kotlin/com/google/firebase/ai/` of firebase-android-sdk, firebase-ai 18.2.1 (`2cfdd03`) |
| `IOS/` | `FirebaseAI/Sources/` of firebase-ios-sdk, FirebaseAILogic 13.3.0 (`cef246f`) |
| `FF/` | `packages/firebase_ai/firebase_ai/lib/src/` of FlutterFire, firebase_ai 5.2.0 (`bbdc38e`) |

"Pinned by" names a test file and test name, relative to `firebase_ai/firebase_ai_dart/test/`.

## Departures from upstream

### Row 1. Every non-2xx answer is an exception

**Decision.** Every non-2xx answer is a `FirebaseAIException` with the HTTP status, the server's status, the reason and
a sanitized message.

**Why.** FlutterFire decodes any status below 500 as a response (`FF/client.dart:75-81`), so a non-JSON 4xx becomes a
`FormatException`; its stream yields an error body as a chunk (`FF/client.dart:98`).

**Rejected.** FlutterFire's decoding.

**Pinned by.** `errors_test.dart`: "404 with an HTML body"; `stream_test.dart`: "stream 400 is an exception".

Status: designed.

### Row 2. The unary deadline covers the body

**Decision.** The deadline of a unary call lasts until the whole body is read.

**Why.** JS clears its timer when the headers arrive (`JS/requests/request.ts:306-310`), so a stalled body hangs
forever.

**Rejected.** JS's timer.

**Pinned by.** `timeout_test.dart`: "stalled unary body times out".

Status: designed.

### Row 3. The aggregate keeps usage; every event is emitted

**Decision.** The internal aggregate of a stream keeps the last `usageMetadata`, and every event that decodes is
emitted.

**Why.** JS's aggregate has no `usageMetadata` (`JS/requests/stream-reader.ts:239-241`), and its stream hides
usage-only events (`:164-172`), which hides the final usage event.

**Rejected.** JS's filtering.

**Pinned by.** `stream_test.dart`: "usage of the last event".

Status: designed.

### Row 4. One history rule for unary and stream sends

**Decision.** A chat appends the message and the reply together, only when the first candidate has parts and no
blocking finish reason. The same rule holds for `sendMessage` and `sendMessageStream`.

**Why.** JS's unary send appends the user message even when no candidate came back
(`JS/methods/chat-session-base.ts:173,217`). JS also appends blocked candidates, against its own documentation
(`:88-92` against `:183-194`). The next send would replay a blocked answer.

**Rejected.** JS's code. Android never appends a candidate whose finish reason is not `STOP`, because its `validate()`
throws first (`AND/common/APIController.kt:493-502`); here `MAX_TOKENS` and `OTHER` replies are appended, because their
accessors do not throw.

**Pinned by.** `chat_test.dart`: "blocked prompt leaves history unchanged", "SAFETY reply is not appended".

Status: designed.

### Row 5. No per-role part table in history validation

**Decision.** `startChat(history:)` checks the first role, the alternation of roles and that no content is empty. It
does not check which part types each role may carry.

**Why.** JS rejects model `inlineData` in a restored history (`JS/methods/chat-session-helpers.ts:34-40`), although image
and code-execution replies put such parts in the history. A fixed table drifts from the server.

**Rejected.** JS's table.

**Pinned by.** `chat_test.dart`: "restored history with an image reply".

Status: designed.

### Row 6. `models/<name>` gives `models/<name>`

**Decision.** A model name with a leading `models/` is accepted, and the prefix is removed. Other `/` forms are an
`ArgumentError`.

**Why.** JS sends `models/models/x` on the Developer API (`JS/models/ai-model.ts:89-91`). Custom resource forms
(tuned models) are a non-goal: Android and iOS hard-code the model path too, and nothing shows the proxy serves them.

**Rejected.** Passing `/` forms into the path as JS does for Agent Platform: per-segment validation can be added later.

**Pinned by.** `model_name_test.dart`: "name table".

Status: designed.

### Row 7. Missing safety fields stay null

**Decision.** On the Developer API, a missing `severity`, `probabilityScore` or `severityScore` decodes as null.

**Why.** JS invents `HARM_SEVERITY_UNSUPPORTED` and scores of 0 (`JS/googleai-mappers.ts`
`mapGenerateContentCandidates`).

**Rejected.** JS's invented defaults.

**Pinned by.** `backend_mapping_test.dart`: "missing severity is null".

Status: designed.

### Row 8. No code from message text

**Decision.** The exception code comes from the envelope's status and the HTTP status, never from message text. The
machine-readable cause is `reason`, from the first `ErrorInfo` detail. `api-not-enabled` is set only for
`SERVICE_DISABLED` of the AI Logic service.

**Why.** Android and FlutterFire match English messages (`FF/error.dart:152` onwards), which breaks on any rewording.
JS matches a link description (`JS/requests/request.ts:256-262`).

**Rejected.** Matching message text or link descriptions.

**Pinned by.** `errors_test.dart`: "reason from ErrorInfo", "SERVICE_DISABLED for another service".

Status: designed.

### Row 9. Caps, a bounded SSE decoder, a depth guard, refused redirects, fixed origin, redaction

**Decision.** Success bodies, error bodies, stream events and streams have size caps; JSON nesting over 128 levels is
refused; the SSE decoder is bounded; redirects are never followed; the origin is fixed at construction; messages and
logs carry no token, key, body, prompt or response text.

**Why.** JS reads `response.json()` with no cap; FlutterFire's line splitter has no cap (`FF/client.dart:102`).

**Rejected.** Caps an app may change: a setting apps can set badly. Raising a cap is a patch release.

**Pinned by.** `security/limits_test.dart`, `security/hosts_test.dart`, `security/leakage_test.dart`: every case.

Status: designed.

### Row 11. An empty part object is dropped

**Decision.** A part with no keys at all is dropped from a response instead of failing the whole stream.

**Why.** JS throws `invalid-content` during aggregation (`JS/requests/stream-reader.ts:298-304`), after the chunks were
shown.

**Rejected.** JS's failure.

**Pinned by.** `response_test.dart`: "empty part dropped".

Status: designed.

### Row 12. `countTokens` sends what the model sends

**Decision.** `countTokens` sends the model's system instruction, tools and generation configuration, and strips roles
on the Developer API (iOS's bodies).

**Why.** The count otherwise leaves out what `generateContent` sends. The Developer API counts the role text as prompt
tokens.

**Rejected.** JS and FlutterFire bodies, which send contents only (and, on the Developer API, `model` and `contents`).

**Pinned by.** `request_shape_test.dart`: "count bodies per backend".

Status: designed.

### Row 13. Two idle bounds for a stream

**Decision.** `streamIdleTimeout` (180 seconds, or null for none) gives two bounds: no bytes, and no event. A keep-alive
comment line does not restart the event timer.

**Why.** JS has no deadline once the headers arrive, so a stalled stream hangs forever and blocks a chat. Android and
iOS bound a request by idle time (`AND/common/APIController.kt:153-156`; `IOS/GenerativeAIService.swift:147`).

**Rejected.** Bytes only: a keep-alive comment keeps a stuck stream open. A separate total deadline: one more setting,
and a long answer can legitimately run past any fixed total.

**Pinned by.** `timeout_test.dart`: "stream idle timeout", "keep-alive comment does not restart the timer".

Status: designed.

### Row 14. `retryAfter`

**Decision.** An exception carries `retryAfter` from `RetryInfo` or a `Retry-After` header, clamped to 24 hours. The
client never waits on it.

**Why.** No SDK reads the server's delay, so a client cannot know how long to wait after a 429.

**Rejected.** Automatic retry: a retried generation is billed again.

**Pinned by.** `errors_test.dart`: "retryAfter table".

Status: designed.

### Row 15. Aggregation rules

**Decision.** Per field, the aggregate keeps the last non-null value; the role defaults to `model`; an empty text part
carrying a `thoughtSignature` is kept; every candidate gets an `index`.

**Why.** JS overwrites with undefined (`JS/requests/stream-reader.ts:257-265`), defaults the role to `'user'` (`:287`),
drops the signature-bearing empty part (`:295`), and gives only candidate 0 an index
(`JS/requests/response-helpers.ts:111-116`).

**Rejected.** JS's aggregate.

**Pinned by.** `backend_mapping_test.dart`: "aggregate field table".

Status: designed.

### Row 17a. A failed limited-use mint sends the placeholder

**Decision.** When minting a limited-use App Check token fails, the call proceeds with the placeholder token.

**Why.** JS fails the call (the headers are awaited before `fetch`, `JS/requests/request.ts:231`; the limited-use call
rejects, `JS/models/utils.ts:63-65`). Android and iOS send the placeholder, as this client does. Enforcement is the
project's setting, and the four products on the shared seam (Functions, AI Logic, App Check, Data Connect) share one
rule.

**Rejected.** Failing locally: AI Logic would differ from the other products on one seam, and the client would decide
what the project's enforcement setting decides.

**Pinned by.** `tokens_test.dart`: "limited-use mint failure sends the placeholder".

Status: designed.

### Row 17b. A provider that cannot mint limited-use tokens sends no header

**Decision.** With `useLimitedUseAppCheckTokens`, a provider that does not implement `LimitedUseAppCheckTokenProvider`
gives no App Check header, and the call proceeds. The instance warns once.

**Why.** iOS throws (`IOS/Types/Internal/AppCheck.swift:31-47`); the same reason as row 17a.

**Rejected.** iOS's throw.

**Pinned by.** `tokens_test.dart`: "provider without limited-use support sends no header".

Status: designed.

### Row 18. No-candidate accessors throw only with a block reason

**Decision.** With no candidate, `text`, `thoughtSummary`, `inlineDataParts` and `functionCalls` throw only when
`promptFeedback.blockReason` is set.

**Why.** JS throws on any `promptFeedback` (`JS/requests/response-helpers.ts:139-149`), but JS's stream drops such
chunks (`JS/requests/stream-reader.ts:164-172`). This client emits every event, so JS's rule would make `chunk.text`
throw on a harmless chunk in a plain loop.

**Rejected.** JS's rule.

**Pinned by.** `finish_reason_test.dart`: "promptFeedback without blockReason does not throw".

Status: designed.

## Choices against Android and iOS that are not departures

JS is the reference for these, so they are rows of [ai_logic_parity.md](ai_logic_parity.md) and not departures:

- **Finish reasons do not throw on receipt.** `generateContent`, every stream chunk and every chat send return the
  response. Only the four accessors throw `response-error`, for a response with no candidate and a block reason, or for
  the 16 blocking finish reasons of JS. `MAX_TOKENS`, `OTHER`, `STOP` and unknown values never throw. Android and iOS
  throw on receipt, which loses billed partial answers (`MAX_TOKENS`), fails streams after their chunks were shown, and
  breaks deployed apps when the server adds a finish reason.
- **The token rule.** The shared rule of the App Check seam (rows 17a and 17b) and one 401 rule: after a 401 the client
  invalidates the Auth token if it sent one, never resends, and never invalidates App Check.

## Decisions that bind phase 2 (0.2.0)

Phase 2 (Live over WebSocket, server prompt templates, automatic function calling) has its own specification. These
decisions are made now so that 0.1.0 does not contradict them. They have no 0.1.0 code and no 0.1.0 test.

### P1. Live puts the API key in a header on the VM

**Decision.** On the VM, Live puts the API key in `x-goog-api-key` and not in a `?key=` query, together with the full
header set, as iOS does (`IOS/Types/Internal/Live/LiveSessionService.swift:393-395`). Each connect and each resumption
asks for its own limited-use token.

**Why.** JS and Android put the key in the URL, where proxies and servers log it.

**Rejected.** JS's and Android's form.

### P2. Live on the web puts the API key in the URL and sends no tokens

**Decision.** On the web, Live puts the API key in the URL query and sends no App Check or Auth token.

**Why.** A browser cannot set WebSocket upgrade headers, and the proxy is not known to accept the key in the first
frame. JS does the same (`JS/requests/request.ts:118-123`, `JS/websocket.ts:86`); FlutterFire's web connector drops
its headers (`FF/web_socket_connect_web.dart:17-22`). The shared specification allows this as one of two departures
from "no secret in a URL", and it concerns the API key only. The phase-2 specification first checks whether the proxy
accepts the key in the first frame; if it does, this departure goes away. Whether a project that enforces App Check
refuses such a session is assumed, not verified (open item O2).

**Rejected.** A VM-only Live, because the web would lose a feature JS ships. A token in the URL, because the proxy
documents no such parameter and it would land in logs.

### P3. Automatic function calling never sends error text to the model

**Decision.** A function that throws, or returns a value `jsonEncode` rejects, fails the send and leaves the history
unchanged. Its error text never goes to the model.

**Why.** JS wraps the error and throws; FlutterFire sends `e.toString()` to the model (`FF/chat.dart:134`), which can
leak local data.

### P4. No `web` dependency in 0.1.0; one WebSocket connector

**Decision.** 0.1.0 has no dependency on `package:web`. The WebSocket connector arrives with 0.2.0, moved from the
Realtime Database package into `_firebase_transport_dart`; there is no product copy.

## FlutterFire probe (step 5)

The lead runs FlutterFire's own `firebase_ai` example on Linux with `firebase_core` resolved to the shim, against
`tool/ai_fake_server.dart` through a rewriting `http.Client`, and records the outcome here: (a) it works, so the docs
say to use FlutterFire `firebase_ai` with the Dart core on Linux; (b) it works without App Check and Auth, so a later
`firebase_ai_dart_platform` registers those services backed by this SDK's providers; or (c) it fails, so apps use
`firebase_ai_dart` directly. Phase 1 ships no adapter in any case.

Outcome: not recorded yet. The lead fills this in.

## Alternatives considered

| Question | Chosen | Rejected, and why |
|---|---|---|
| Transport | REST and server-sent events; WebSocket for Live | gRPC: no published protos, no SDK uses it, unknown metadata handling, no web |
| Public API shape | FlutterFire's names and call shapes, without its static cache | (a) The JS shape (`getAI`, `getGenerativeModel`, `{stream, response}`): written for promises and async generators, and FlutterFire apps would rewrite every call. (b) A fresh design: the same rewrite, with no gain |
| FlutterFire adapter | none in 0.1.0; the step 5 probe first | An adapter now: `firebase_ai` is Dart over `package:http`, and its only native call answers `{}` when no plugin exists (`FF/platform_header_helper.dart:38-51`), so the probe may show no adapter is needed |
| Instances | named constructors, one instance per call | FlutterFire's static map (`FF/firebase_ai.dart:62,76`) and JS's `already-initialized` (`JS/api.ts:102-118`): no global state |
| Model layer | hand-written immutable classes with `raw` | (a) Generated from protos: the proxy's protos are not published. (b) Plain maps: no type checks, and FlutterFire apps expect classes |
| Unknown response data | lenient decoding, `raw`, `unknown` enum values, `UnknownPart` | Strict decoding: the API adds fields and enum values between releases, and a strict client breaks on each |
| Request validation | client-protecting checks only | Copying server rules (MIME patterns, name patterns, part tables): they drift and reject valid requests |
| Stream result | `Stream<GenerateContentResponse>`; the aggregate stays internal | A public aggregate (JS's `{stream, response}` or a `collect()`): it fixes the merge rules as an API contract |
| Backend differences | port JS's field renames; refuse `SafetySetting.method` locally | Let the server reject everything: the Developer API's citation field would silently decode as absent |
| Error codes | canonical status codes plus a few AI codes; `reason`; `retryAfter` | (a) JS's `fetch-error` for every status. (b) FlutterFire's exception classes, built from message matching |
| History bound | none; apps trim | (a) A count cap: rejects long but valid chats. (b) Automatic trimming: changes what the model sees without the app knowing |
| Blocked replies in history | not appended | JS's code, which appends them: the next send replays a blocked answer |
| Stream liveness | two bounds from `streamIdleTimeout`: no bytes (shared helper), no event (this client) | (a) Bytes only: a keep-alive comment keeps a stuck stream open. (b) A separate total deadline: one more setting, and a long answer can legitimately run past any fixed total |
| Chat stream queue slot | taken on listen | Taken at call time: a stream that is never listened to blocks every later send |
| Per-call cancel | `abortTrigger` and `timeout` on every call | `close()` only: stopping one request kills every request of the instance |
| 401 | `invalidate(TokenKind.auth)` when an Auth token was sent; no resend | One resend: could bill twice if the proxy answers 401 after generation (unknown, kit check K10); no SDK resends |
| Retries | none; `retryAfter` exposed | Automatic retry: a retried generation is billed again |
| Token failures | the shared rule of the App Check seam | (a) Fail locally when a limited-use token cannot be had (JS on a failed mint, iOS on a missing capability): AI Logic would differ from Functions and Data Connect on one seam, and the client would decide what the project's enforcement setting decides. (b) Android's single 10 s budget for both tokens: a slow App Check provider would also remove the user's identity |
| Finish reasons | JS: accessors throw | Android and iOS: throw on receipt, `MAX_TOKENS` included. That loses billed partial answers, fails streams after their chunks were shown, and throws on any finish reason it does not know |
| No-candidate accessors | throw only with a `blockReason` | JS's "any `promptFeedback`": with every event emitted, a harmless chunk would throw in a plain loop (row 18) |
| Data-collection header | follow `app.isAutomaticDataCollectionEnabled` per request | A per-instance flag: an app that turned data collection off would still send the app id |
| Shared helpers | `_firebase_transport_dart` as a prerequisite | Local copies: a third copy of security-critical helpers |
| Identity headers for restricted keys | none | A `headers` option with the three names (as Installations has): a value typed by a non-mobile build is a false claim to the key restriction; the App Check client made the same choice |
| Tuned and custom models | not supported in 0.1.0 | Passing `/` forms into the path as JS does: Android and iOS do not, nothing shows the proxy serves them, and per-segment validation can be added later |
| Caps | fixed | Caps an app may change: a setting apps can set badly; raising a cap is a patch release |
