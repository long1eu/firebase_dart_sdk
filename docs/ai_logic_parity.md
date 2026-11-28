# AI Logic parity with the JS, Android, iOS and FlutterFire SDKs

This document compares the public API and the behaviour of the AI Logic clients of three official SDKs and of FlutterFire's `firebase_ai` with `firebase_ai_dart` (`firebase_ai/firebase_ai_dart`), feature by feature:

- **JS**: `packages/ai` of firebase-js-sdk 3.1.0 at `a086865`. It is the reference for the protocol and for the request and response shapes.
- **Android**: `ai-logic/firebase-ai` of firebase-android-sdk (firebase-ai 18.2.1) at `2cfdd03`.
- **iOS**: `FirebaseAI` of firebase-ios-sdk (FirebaseAILogic 13.3.0) at `cef246f`. It is the reference for the `countTokens` bodies.
- **FlutterFire**: `firebase_ai` 5.2.0 at `bbdc38e`. It is the reference for the shape of the Dart API.
- **Dart**: `firebase_ai_dart` 0.1.0. The Dart column states the behaviour the package is specified to have. The code and its tests are written after this document, so read each row as the design until the tests pass.

The C++ SDK has no AI Logic client. The SDKs were read as source clones; their code was read, not run. Line numbers will drift. A cell that says "not compared" was not read for this table. The reasons for each departure, the alternative that was rejected and the test that pins it are in [ai_logic_decisions.md](ai_logic_decisions.md); the notes below name them as rows.

The Status column compares the Dart behaviour with the SDK named in the cell, or with all of them when it names none:

- **same**: the behaviour of the SDK named in the cell, or of all of them
- **different**: a deliberate change, with the reason in the notes
- **missing**: not in 0.1.0; the notes say when it is planned
- **won't do**: the notes give the reason

Path shorthand:

- `J:` is JS `packages/ai/src`.
- `A:` is Android `ai-logic/firebase-ai/src/main/kotlin/com/google/firebase/ai`.
- `I:` is iOS `FirebaseAI/Sources`.
- `F:` is FlutterFire `packages/firebase_ai/firebase_ai/lib/src`, and `FFPKG:` is that package's root.
- `GF:` is the goldfish notes (`parity_matrix.md`, `research_check.md`), which are working notes of this project and not in the repository.

## Summary

39 feature rows in 6 groups.

| Status | Rows |
|---|---|
| same | 12 |
| different | 21 |
| missing | 2 |
| won't do | 4 |

## What the Dart package is for

FlutterFire's `firebase_ai` asks the app's `firebase_app_check` and `firebase_auth` services for its tokens, and those have no Linux plugin; Android and iOS exist only on their platforms. `firebase_ai_dart` is a Firebase AI Logic client for the Dart VM (macOS, Windows, Linux, servers, command-line tools) and the web (dart2js, dart2wasm), with App Check and Auth tokens from the providers of a `FirebaseApp`, bounded reads of every response, and no Flutter dependency.


## Responses and finish reasons

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Finish reasons | accessors throw for a blocked prompt or one of 16 finish reasons J:requests/response-helpers.ts (`badFinishReasons`) | throws on receipt: `PromptBlockedException` for a block reason, `ResponseStoppedException` for any finish reason other than `STOP`, `MAX_TOKENS` included A:common/APIController.kt:493-502 | throws on receipt: `promptBlocked`, and `responseStoppedEarly` when the first candidate's reason is not `STOP` I:GenerativeModel.swift:286-294,330-340 | `text` throws for a blocked prompt or for `SAFETY` and `RECITATION` only F:api.dart:65-91 | JS's rule: `generateContent`, every chunk and every chat send return the response; `text`, `thoughtSummary`, `inlineDataParts` and `functionCalls` throw `response-error` for a block reason with no candidate or for the 16 reasons. `MAX_TOKENS`, `OTHER`, `STOP` and unknown values never throw | same (JS) | A partial answer ending in `MAX_TOKENS` is billed and usable; a stream would otherwise fail after its chunks were shown; and a finish reason added by the server would break deployed apps on Android's rule. An app that wants Android's behaviour checks `candidates.first.finishReason`. FlutterFire apps meet 14 more throwing reasons. |
| Accessors with no candidate | throw on any `promptFeedback` J:requests/response-helpers.ts:139-149, but the stream drops such chunks J:requests/stream-reader.ts:164-172 | not applicable: throws on receipt | not applicable: throws on receipt | `text` throws for a blocked prompt F:api.dart:65-91 | throw only when `promptFeedback.blockReason` is set; otherwise `text` and `thoughtSummary` are null and the lists are empty | different (JS) | This client emits every stream event, so JS's rule would make `chunk.text` throw on a harmless chunk in a plain loop. Decision row 18. |
| Text of several parts | joins the text parts with `''` | joins them with a space GF:parity_matrix.md AI item 1 | not compared | not compared | `text` joins the text parts of the first candidate that are not thoughts with `''` | same (JS) |  |
| Empty part object in a response | fails the aggregation with `invalid-content`, after the chunks were shown J:requests/stream-reader.ts:298-304 | not compared | not compared | not compared | an object with no keys is dropped; a part with unknown keys or invalid base64 becomes an `UnknownPart` | different (JS) | Decision row 11. |
| Missing safety fields (Developer API) | invents `HARM_SEVERITY_UNSUPPORTED` and scores of 0 J:googleai-mappers.ts (`mapGenerateContentCandidates`) | not compared | not compared | not compared | stay null | different (JS) | Decision row 7. |
| Unknown response data | not compared | not compared | not compared | not compared | lenient: a field of the wrong type is absent, an unknown enum string is `unknown`, every response type keeps `raw` | different | The API adds fields and enum values between releases. |

## Streaming

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Usage in a stream | the aggregate has no `usageMetadata` J:requests/stream-reader.ts:239-241; usage-only events are hidden :164-172 | not compared | not compared | not compared | every decoded event is emitted; the aggregate keeps the last `usageMetadata` | different (JS) | Decision row 3. |
| Aggregate rules | overwrites with undefined J:requests/stream-reader.ts:257-265; role defaults to `'user'` :287; drops an empty part with a signature :295; only candidate 0 gets an index J:requests/response-helpers.ts:111-116 | not compared | not compared | not compared | last non-null value per field; role `model`; an empty text part with a `thoughtSignature` is kept; every candidate has an `index`; the aggregate is internal | different (JS) | Decision row 15. |
| Stream idle bounds | none after the headers: a stalled stream hangs forever | idle time; 180 s is its minimum socket timeout A:common/APIController.kt:153-156 | bounded by `URLRequest.timeoutInterval` I:GenerativeAIService.swift:147 | not compared | two bounds from `streamIdleTimeout` (180 s, or null for none): no bytes, and no event; keep-alive comments do not restart the event timer | different (JS) | Decision row 13. |
| SSE parsing | single-line regex; accepts `\r\r` and `\r\n\r\n`; strict UTF-8 J:requests/stream-reader.ts:40,57-59 | not compared | not compared | line splitter with no cap F:client.dart:102 | a bounded decoder (64 MiB per event, 256 MiB per stream); a document split over several `data:` lines is one event; strict UTF-8 | different | Decision row 9. |

## Chat

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| History of a reply that is not `STOP` | appends blocked candidates, against its own documentation J:methods/chat-session-base.ts:88-92 against :183-194; also appends the user message when no candidate came back :173,217 | never appends: `validate()` throws first A:common/APIController.kt:493-502 | not compared | not compared | message and reply are appended together, only when the first candidate has parts and no blocking finish reason; `MAX_TOKENS` and `OTHER` replies are appended | different (JS) | One rule for unary and stream sends. Decision row 4. |
| History validation | a part table per role; rejects model `inlineData` J:methods/chat-session-helpers.ts:34-40 | not compared | not compared | not compared | first role `user`, alternating roles, no empty content; no part table | different (JS) | Decision row 5. |
| Concurrent sends | serialized by a send promise J:methods/chat-session-base.ts:141-149 | not compared | not compared | a mutex, taken at the call; the stream is buffered F:chat.dart:88,166-240 | serialized; `sendMessageStream` takes its place when listened to | different (FlutterFire) | A stream that is never listened to blocks nothing. |

## Requests

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| `countTokens` body (Developer API) | `{generateContentRequest: {model, contents}}` only J:googleai-mappers.ts (`mapCountTokensRequest`) | the same wrapper with the roles kept A:common/Request.kt:62-71 | the whole generate request with the model's configuration, `model` as `models/{name}`, roles removed I:GenerativeModel.swift:208-250 | `{contents}` F:api.dart:1617-1626 | iOS's body | different (iOS) | Decision row 12. The Developer API counts role text as prompt tokens. |
| `countTokens` body (Agent Platform) | `{contents}` J:methods/count-tokens.ts | the flat shape plus `model` A:common/Request.kt:73-80 | flat: `contents`, `systemInstruction`, `tools`, `generationConfig` I:Types/Internal/Requests/CountTokensRequest.swift:53-83 | `{contents}` F:api.dart:1617-1626 | iOS's flat body, with no `safetySettings`, `toolConfig` or `model` | different (iOS) |  |
| `model` field in a generate body | none J:methods/generate-content.ts | sends one A:common/Request.kt:35-43 | none I:GenerateContentRequest.swift:34-58 | not compared | none | same (JS, iOS) |  |
| Model names | `models/x` becomes `models/models/x` on the Developer API; Agent Platform passes other `/` forms J:models/ai-model.ts:89-108 | hard-coded model path A:FirebaseAI.kt:119 | refuses `/` in a name I:FirebaseAI.swift:256-263 | not compared | `models/x` is `x`; any other `/` form is an `ArgumentError` | different (JS) | Decision row 6. Tuned and custom models are not supported in 0.1.0. |
| Schema type names | lower case J:types/schema.ts | not compared | not compared | upper case F:schema.dart:546-555 | upper case (the proto enum names) | same (FlutterFire) | Both forms are in production use, so the proxy accepts both (inferred). |
| `X-Firebase-AppId` | sent when data collection is on J:requests/request.ts:163-165 | sent when data collection is on A:common/APIController.kt:271-272 | sent when data collection is on; also sends `X-Firebase-AppVersion` I:Extensions/Internal/FirebaseInfo+Headers.swift:76-80 | not compared | sent while `app.isAutomaticDataCollectionEnabled` is true, read at each request; no `X-Firebase-AppVersion` | same |  |
| API version and origin | `v1beta` at `firebasevertexai.googleapis.com` J:constants.ts:24-29 | not compared | not compared | hard-coded origin F:base_model.dart:81,96,145 | `v1beta`, one constant; the origin is fixed at construction (`serverOrigin` for tests only) | same (JS) |  |

## Tokens, errors and deadlines

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Limited-use App Check: failed mint | the call fails: the headers are awaited before `fetch` J:requests/request.ts:231, J:models/utils.ts:63-65 | sends the placeholder A:common/AppCheckHeaderProvider.kt:49-55 | sends the placeholder I:Types/Internal/AppCheck.swift:72-75 | not compared | sends the placeholder | same (Android, iOS) | Decision row 17a. Whether the project then refuses the call depends on its App Check enforcement. |
| Limited-use App Check: provider cannot mint | not applicable: JS's App Check always can | not applicable | the call throws I:Types/Internal/AppCheck.swift:31-47; a `fatalError` sits behind `#if Debug` | not compared | no `X-Firebase-AppCheck` header, one warning, and the call proceeds | different (iOS) | Decision row 17b. |
| Token wait | no deadline on the token wait | one 10 s timeout around all header generation; on timeout neither token is sent A:common/APIController.kt:294, A:common/AppCheckHeaderProvider.kt:32-33 | not compared | not compared | each provider has its own wait (the App Check provider answers within 8 s, the shared token source waits 10 s for Auth); only an Auth timeout fails the call; all of it inside the call's own deadline | different (Android) | No SDK other than Android puts a deadline on the token wait. |
| Auth provider does not answer | not compared | neither token is sent (see the row above) | not compared | not compared | the call fails with `unavailable` (`httpStatus` null) after 10 s, or `deadline-exceeded` if the call's deadline passes first | different (Android) | An Auth failure that is not a timeout is `unauthenticated`. |
| After a 401 | not compared | not compared | not compared | not compared | `invalidate(TokenKind.auth)` when an Auth token was sent; no resend; App Check is never invalidated | same | No SDK resends AI calls (GF:research_check.md AI item 5): a retried generation is billed again. |
| Unary deadline | the timer is cleared when the headers arrive J:requests/request.ts:306-310, so a stalled body hangs | not compared | not compared | not compared | the deadline lasts until the whole body is read | different (JS) | Decision row 2. |
| Error codes | `fetch-error` for every status; a link description is matched for the API-not-enabled case J:requests/request.ts:256-262 | matches English messages A:common/APIController.kt:427-463 | not compared | decodes any status below 500 as a response, and matches messages F:client.dart:75-81, F:error.dart:152 | every non-2xx is an exception; the code comes from the status; `reason` carries the machine-readable cause; `api-not-enabled` only for the AI Logic service | different | Decision rows 1 and 8. |
| `retryAfter` | not read | not read | not read | not read (searched J:, A:, I: and F:: no match) | set from `RetryInfo` or `Retry-After`, clamped to 24 h; the client never waits on it | different | Decision row 14. |
| Automatic retries | none | none | none | none | none | same | A retrying `http.Client` bills a generation twice; the README says so. |

## Features and platforms

| Feature | JS | Android | iOS | FlutterFire | Dart | Status | Notes |
|---|---|---|---|---|---|---|---|
| Live (WebSocket) key placement | `?key=` in the URL, no tokens J:requests/request.ts:118-123, J:websocket.ts:86 | key in the URL | `x-goog-api-key` header I:Types/Internal/Live/LiveSessionService.swift:393-395 | the web connector drops its headers F:web_socket_connect_web.dart:17-22 | not in 0.1.0. Planned for 0.2.0: header on the VM (iOS's form), URL query and no tokens on the web (JS's form) | missing | Specification section 7 (P1, P2); decided before any Live code. |
| Server prompt templates, automatic function calling | automatic function calling; a failing function is wrapped and thrown | not compared | not compared | automatic function calling; sends `e.toString()` of a failing function to the model F:chat.dart:134 | not in 0.1.0 | missing | Planned for 0.2.0 with its own specification. A failing function will fail the send and its error text will never go to the model (decisions, P3). |
| Cached content | reads `cachedContentTokenCount` | reads `cachedContentTokenCount` | reads `cachedContentTokenCount` | reads `cachedContentTokenCount` | reads `cachedContentTokenCount`; no request API | same | No SDK has a cached-content request API. |
| Imagen | removed | removed | removed | removed (`FFPKG/CHANGELOG.md:43`) | none | won't do | The Imagen models were shut down; no `:predict` call exists in JS, Android or iOS. |
| On-device and hybrid inference | Chrome's Prompt API J:methods/chrome-adapter.ts | a separate `firebase-ai-ondevice` module | not compared | not compared | none | won't do | Neither exists for a pure-Dart program. |
| Microphone and speaker helpers | not compared | not compared | not compared | `startAudioConversation` | none | won't do | They need platform audio and belong in a Flutter layer. |
| `X-Firebase-Client` heartbeat | not required | not required | not required | not required | not sent | won't do | The repository has no heartbeat service, and no AI SDK requires it. |
| Emulator | none | none | none | none | none | same | None exists for AI Logic in the Firebase CLI; the tests use a fake server. |
| gRPC | no | no | no | no | no | same | No published protos, and no web support. |
| Instances | `getAI` with `already-initialized` J:api.ts:102-118 | not compared | not compared | a static instance map F:firebase_ai.dart:62,76 | named constructors; two calls give two instances; `close()` | different | No global state. |
