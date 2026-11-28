# AI Logic

`firebase_ai_dart` is the Firebase AI Logic client of this repository: pure Dart, the REST and server-sent-event
protocol of the Firebase JS SDK, no plugin and no native code, on the Dart VM (macOS, Windows, Linux) and the web
(dart2js and dart2wasm). It calls Gemini models through Firebase, with the App Check and Firebase Auth tokens of a
`FirebaseApp`. The package is at 0.1.0 and not published yet. This guide covers setting it up on each platform, App
Check and Auth, generating, streaming, chat, multimodal input, function calling, structured output, safety, thinking
and tools, timeouts and cancel, your own HTTP client, errors, limits, security, and moving from FlutterFire. How it
compares with the official SDKs is in [ai_logic_parity.md](../ai_logic_parity.md); why it differs is in
[ai_logic_decisions.md](../ai_logic_decisions.md).

There is no emulator for AI Logic. The tests use a fake server, and nothing in them reaches Google. The client has
not run against a production project yet; the production kit
([tool/verify_production_ai](../../tool/verify_production_ai/README.md)) runs checks against your own project.
**Every check, and every call you make, is billed to the project.**

## What you add

Nothing of this change is on pub.dev yet. Depend on the packages from this repository:

```yaml
dependencies:
  firebase_ai_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_ai/firebase_ai_dart
  firebase_app_dart: ^0.2.3
dependency_overrides:
  _firebase_transport_dart:
    git:
      url: https://github.com/long1eu/firebase_dart_sdk
      ref: main
      path: firebase_core/_firebase_transport_dart
```

`_firebase_transport_dart` is an internal package of this repository, which `firebase_ai_dart` uses for the token
rule, the capped send and the stream decoder it shares with the other products. Application code does not import it.

## Set up

Turn on Firebase AI Logic for your project in the Firebase console (AI Logic) and set up the backend you will use.
The app options come from a web app (or any app) registered in the project. The console has no desktop app type, so
desktop and server programs use the same options.

```dart
import 'package:firebase_ai_dart/firebase_ai_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

final FirebaseApp app = FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: '<the API key of the app>',
    appId: '1:1234567890:web:0123456789abcdef',
    projectId: 'my-project',
  ),
);
final FirebaseAI ai = FirebaseAI.googleAI(app: app);
final GenerativeModel model = ai.generativeModel(model: '<a model name>');
```

- **Two backends.** `FirebaseAI.googleAI` uses the Gemini Developer API. `FirebaseAI.agentPlatform` uses Agent
  Platform and takes a `location` (`global` by default, or for example `us-central1`).
- **No default model.** Model names change between releases, so `model` is required. A name is letters, digits, `.`,
  `_` and `-`, up to 128 characters; a leading `models/` is accepted and removed. Tuned and custom model resource
  names are not supported in 0.1.0.
- **Nothing is sent by a constructor.** A malformed value (an API key that is not a valid header value, a project id
  or location that does not fit its pattern, a bad model name, a negative duration) is an `ArgumentError`. A missing
  or empty API key, app id or project id is a `StateError` at the first call that needs it, so a program can
  construct a `FirebaseAI` it does not call.
- **No instance cache.** Two calls give two independent instances. `close()` aborts the requests in flight (they fail
  with `ai-closed`), closes the HTTP client if the instance created it, and makes later calls fail with `ai-closed`.
  It runs by itself when the app is deleted.
- **Logging.** Pass a `logger` (`void Function(AILogLevel, String)`) to see warnings and one info line. It is silent
  when absent. No message contains a token, the API key, a request body, a prompt, a response text or a function
  argument.

## App Check and Auth

Every request carries `x-goog-api-key`. When the app has them, it also carries an Auth token
(`Authorization: Firebase <ID token>`, the scheme is `Firebase`, not `Bearer`) and an App Check token
(`X-Firebase-AppCheck`). The instance reads `app.authProvider` and `app.appCheckProvider` at every request, so a
provider set after the instance was created is used from the next request.

These packages do not attest a device: you supply the tokens. The sources a program can use:

- the App Check client of this repository: a debug provider on a machine you control, a custom provider, or
  reCAPTCHA on the web;
- an `AppCheckTokenProvider` of your own, that asks your server for a token;
- for limited-use tokens, a provider that also implements `LimitedUseAppCheckTokenProvider` and asks your server for
  one token per request.

```dart
class ServerTokenProvider extends AppCheckTokenProvider
    implements LimitedUseAppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async {
    // Ask your own server for a session token here.
    return const AppCheckTokenResult('<a token from your server>');
  }

  @override
  Future<AppCheckTokenResult> getLimitedUseToken() async {
    // Ask your own server for a token that is good for one request.
    return const AppCheckTokenResult('<a limited-use token from your server>');
  }

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

void useProvider(FirebaseApp app) {
  app.appCheckProvider = ServerTokenProvider();
}
```

- **A debug token is a secret** that passes App Check for the whole project. Use it only on machines you control and
  never inside a binary you ship. A distributed app uses a custom provider backed by your own server.
- **Without a provider** the instance logs one `info` line at its first request ("No App Check provider: requests
  carry no App Check token; with App Check enforced for AI Logic they will be refused."). That is a log line and not
  a refusal: whether to enforce App Check is a project setting.
- **Limited-use tokens.** `FirebaseAI.googleAI(app: app, useLimitedUseAppCheckTokens: true)` asks for one token per
  request, every chat send included. A failed mint sends the placeholder token (the service can then tell a failed
  attestation from an app without App Check), and a provider that cannot mint limited-use tokens sends no App Check
  header, with one warning. Neither fails the call: the project's enforcement setting decides what the service does.
  This is the same rule as in the other products built on the App Check seam of `firebase_app_dart`.
- **Auth failures do fail the call.** A provider that throws, or gives something that is not a token, fails the call
  with `unauthenticated`; one that does not answer within 10 seconds fails it with `unavailable`; a token over the
  length limit fails it with `failed-precondition`. All of these happen before anything is sent, and `httpStatus`
  is null.
- **After a 401** the client invalidates the Auth token if it sent one. It never resends the request: a retried
  generation is billed again.
- **`X-Firebase-AppId`** is sent only while `app.isAutomaticDataCollectionEnabled` is true, checked at each request.

### Keys per platform

An API key restricted to Android or iOS apps is refused from desktop, server and web. Use one key per platform,
restricted to the Firebase AI Logic API, with HTTP referrer restrictions on the web. The client sends no
`X-Android-Package`, `X-Android-Cert` or `X-Ios-Bundle-Identifier`: a value typed by a desktop, server or web build
would be a false claim to the key restriction.

## Generate

```dart
final GenerateContentResponse response = await model.generateContent(
  <Content>[Content.text('Write a haiku about Dart.')],
);
print(response.text);
print(response.usageMetadata?.totalTokenCount);
```

A `Content` is a role (`user` by default, or `model`) and a list of parts. `Content.text`, `Content.multi`,
`Content.model`, `Content.inlineData`, `Content.functionResponse` and `Content.functionResponses` build the common
ones. Roles in a prompt are `user`, `model`, `function` or null; a `system` content is refused with a message that
names `systemInstruction`, which is where it belongs.

The model's settings are `safetySettings`, `generationConfig`, `tools`, `toolConfig` and `systemInstruction`, plus
`requestTimeout` and `streamIdleTimeout`. A per-call value of the first four replaces the model's value; it does not
merge with it.

```dart
final GenerativeModel concise = ai.generativeModel(
  model: '<a model name>',
  systemInstruction: Content.system('Answer in one short paragraph.'),
  generationConfig: const GenerationConfig(temperature: 0.4, maxOutputTokens: 400),
);
```

**Blocked and cut-off answers.** `generateContent` returns the response in every case. The four accessors
(`text`, `thoughtSummary`, `inlineDataParts`, `functionCalls`) throw a `FirebaseAIException` with the code
`response-error` when the response has no candidate and `promptFeedback.blockReason` is set, or when the first
candidate ends with one of these 16 finish reasons: `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`,
`SPII`, `MALFORMED_FUNCTION_CALL`, `IMAGE_SAFETY`, `IMAGE_PROHIBITED_CONTENT`, `IMAGE_OTHER`, `NO_IMAGE`,
`IMAGE_RECITATION`, `LANGUAGE`, `UNEXPECTED_TOOL_CALL`, `TOO_MANY_TOOL_CALLS`, `MISSING_THOUGHT_SIGNATURE` and
`MALFORMED_RESPONSE`. `MAX_TOKENS`, `OTHER`, `STOP` and a finish reason this version does not know never throw.
An app that wants the Android behaviour reads `response.candidates.first.finishReason` itself:

```dart
final FinishReason? reason = response.candidates.first.finishReason;
if (reason == FinishReason.maxTokens) {
  print('The answer was cut off, but it is usable: ${response.text}');
}
```

Only the first candidate is examined by the accessors; the others are in `candidates`. `text` joins the text parts
that are not thoughts with an empty string.

**Reading what the library does not model.** Every response type has `raw`, the decoded JSON object, so a field this
version does not model is still readable. Decoding is lenient: a field of the wrong type is treated as absent, and an
unknown enum string becomes `unknown`.

### Count tokens

```dart
final CountTokensResponse count = await model.countTokens(
  <Content>[Content.text('How many tokens is this?')],
);
print(count.totalTokens);
```

`countTokens` sends the model's system instruction, tools and generation configuration too, so the count matches
what `generateContent` would send.

## Stream

```dart
final Stream<GenerateContentResponse> chunks = model.generateContentStream(
  <Content>[Content.text('Tell me a short story.')],
);
await for (final GenerateContentResponse chunk in chunks) {
  print(chunk.text ?? '');
}
```

- The arguments are checked when you call the method (an `ArgumentError` is thrown before the stream is returned).
  The request is sent when the stream is listened to. The stream is single-subscription.
- Every event that decodes is emitted, in order, including events that carry only `usageMetadata` or
  `promptFeedback`. A chunk without text has `text == null`. The last chunk usually has the finish reason and the
  usage.
- An error event, a malformed event, a cap or an idle bound ends the stream with an error. When it fails after at
  least one chunk, the exception's `response` holds the aggregate of the chunks already emitted, so a billed partial
  answer is not lost.
- Cancelling the subscription aborts the request and is not an error.
- **Idle bounds.** `streamIdleTimeout` (180 seconds by default) gives two bounds, both reporting
  `deadline-exceeded`: no bytes for that long, and no event for that long. A keep-alive comment line is bytes but not
  an event, so it cannot keep a stalled stream open. `streamIdleTimeout: null` turns both off; then only the call's
  `timeout` before the headers and the `abortTrigger` remain.

## Chat

```dart
final ChatSession chat = model.startChat();
final GenerateContentResponse first = await chat.sendMessage(
  Content.text('My favourite number is 42.'),
);
print(first.text);
await for (final GenerateContentResponse chunk in chat.sendMessageStream(
  Content.text('What is my favourite number?'),
)) {
  print(chunk.text ?? '');
}
print(chat.history.length); // 4
```

- **The history rule.** The message and the reply are appended together, and only when the first candidate's content
  has at least one part and its finish reason is not blocking (the 16 reasons above). Otherwise the history is
  unchanged: after an exception, a cancel, a timeout, a prompt blocked with no candidate, a candidate with no parts, or
  a blocking finish reason. A reply that ends with `MAX_TOKENS` or `OTHER` is appended. Each successful turn adds
  exactly two entries. The rule is the same for `sendMessage` and `sendMessageStream`; for a stream it is applied to
  the aggregate of all chunks once the stream ended without error.
- **A message** has role `user` (null counts as `user`) and at least one part. It holds either only function-response
  parts or none.
- **Sends are serialized.** A send starts after the previous one finished, whether it completed, failed, was cancelled
  or timed out. `sendMessageStream` takes its place in the queue when the stream is listened to, so a stream that is
  never listened to blocks nothing. A paused subscription keeps its place, and both idle timers stop while it is
  paused: **cancel** a chat stream the app no longer reads instead of pausing it.
- **Starting from a history.** `startChat(history: ...)` requires that the first content has the role `user`, that
  every role is `user`, `model` or `function`, that no content is empty, and that user-side and model turns
  alternate; a failure is an `ArgumentError` naming the index. The `function` role is accepted so that histories saved
  by older SDKs load; this client sends function responses with the role `user`. There is no per-role check of part
  types.
- **Saving a history.** `history` is plain data: `Content.toJson()` and `Content.fromJson()` round-trip it. Chat
  history lives in memory only; the app stores it if it needs it.
- **Cost.** Each turn resends the whole history, so the input tokens of a conversation grow roughly with the square of
  the number of turns. A `countTokens` call before each turn adds a request against the same quota, and with
  limited-use App Check each send also costs one token mint on your server. Cap the turns, or summarize older turns
  into one message, and call `countTokens` only when the history has grown.
- **Trimming.** There is no cap and no automatic trimming: the model's context window bounds a request, and the
  server is expected to answer `invalid-argument` beyond it. To check the size, call `countTokens(chat.history)` on a
  model created with the chat's settings, then start a new session from a shorter or summarized history (below). A
  trimmed history must still start with a `user` content and alternate roles, so cut an even number of entries from
  the front.
- **Media in a kept history.** Image and audio replies are held as base64 in `raw` plus decoded bytes (about 2.3 times
  one copy) and are re-encoded on every later turn. Drop media turns from a history you keep if you do not need them.

```dart
final int used = (await model.countTokens(chat.history)).totalTokens;
if (used > 20000) {
  final ChatSession shorter = model.startChat(
    history: chat.history.sublist(chat.history.length - 6),
  );
  print(shorter.history.length);
}
```

## Multimodal input

```dart
import 'dart:typed_data';

final Uint8List png = Uint8List.fromList(<int>[/* the bytes of an image */]);
final GenerateContentResponse described = await model.generateContent(<Content>[
  Content.multi(<Part>[
    const TextPart('What is in this picture?'),
    InlineDataPart('image/png', png),
  ]),
]);
print(described.text);
```

- **Inline data** (`InlineDataPart`, or `Content.inlineData`) goes into the JSON request as base64. While a request
  runs the data is held about 3.7 times over (the bytes, the base64 string, the encoded body): a 20 MB image takes
  about 75 MB. The service's limit for inline data, and the error it returns past it, are not settled yet.
- **File URIs** (`FileData(mimeType, fileUri)`) point at media the service can read itself; use them for large media.
  Which URI schemes each backend accepts is not settled yet either; the production kit checks them.
- **Image and audio output.** `GenerationConfig.responseModalities`, `speechConfig` and `imageConfig` are passed
  through. Image replies come back as `InlineDataPart`s (`response.inlineDataParts`). `imageConfig.aspectRatio` and
  `imageSize` are strings, because the service adds values over time.

## Function calling

Function calling is manual in 0.1.0: the model asks for a function, the program runs it and sends the result back.
Automatic function calling arrives in 0.2.0.

```dart
final GenerativeModel withTools = ai.generativeModel(
  model: '<a model name>',
  tools: <Tool>[
    Tool.functionDeclarations(<FunctionDeclaration>[
      FunctionDeclaration(
        'current_weather',
        'The current weather in a city.',
        parameters: Schema.object(
          properties: <String, Schema>{
            'city': Schema.string(description: 'The name of the city.'),
          },
        ),
      ),
    ]),
  ],
  toolConfig: const ToolConfig(
    functionCallingConfig: FunctionCallingConfig(mode: FunctionCallingMode.auto),
  ),
);
final ChatSession toolChat = withTools.startChat();
GenerateContentResponse step = await toolChat.sendMessage(
  Content.text('What is the weather in Cluj-Napoca?'),
);
while (step.functionCalls.isNotEmpty) {
  final List<FunctionResponse> results = <FunctionResponse>[
    for (final FunctionCall call in step.functionCalls)
      FunctionResponse(call.name, <String, Object?>{'sky': 'clear'}, id: call.id),
  ];
  step = await toolChat.sendMessage(Content.functionResponses(results));
}
print(step.text);
```

- The calls are in `response.functionCalls`; the model may ask for several functions in one reply. Answer all of them in
  one `Content.functionResponses`. Give a loop like the one above a limit in a real program.
- Send the model's reply back as it came. A reply that loses its thought signature can end with
  `MISSING_THOUGHT_SIGNATURE`; the chat session keeps replies as received.
- `FunctionCallingMode.any` forces a call, `none` forbids one, and `allowedFunctionNames` narrows the choice.

## Structured output

```dart
final GenerativeModel json = ai.generativeModel(
  model: '<a model name>',
  generationConfig: GenerationConfig(
    responseMimeType: 'application/json',
    responseSchema: Schema.object(
      properties: <String, Schema>{
        'title': Schema.string(),
        'minutes': Schema.integer(),
        'vegetarian': Schema.boolean(),
      },
      optionalProperties: <String>['vegetarian'],
    ),
  ),
);
final GenerateContentResponse answer = await json.generateContent(
  <Content>[Content.text('Give me one quick dinner idea.')],
);
print(answer.text);
```

- `responseSchema` takes a `Schema`, an OpenAPI subset: `string`, `enumString`, `integer`, `number`, `boolean`,
  `array`, `object` and `anyOf`. `required` is every property that is not in `optionalProperties`. Type names go out
  in upper case.
- `responseJsonSchema` takes a `JsonSchema`, which is sent verbatim.
- The schema shapes the answer. The program still decodes and checks it: `jsonDecode(response.text!)` can fail.

## Safety, thinking and tools

```dart
final GenerativeModel careful = ai.generativeModel(
  model: '<a model name>',
  safetySettings: <SafetySetting>[
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.low),
  ],
  generationConfig: const GenerationConfig(
    thinkingConfig: ThinkingConfig.withThinkingBudget(1024, includeThoughts: true),
  ),
  tools: <Tool>[Tool.googleSearch()],
);
```

- **Safety.** Ratings are in `candidate.safetyRatings` and `promptFeedback.safetyRatings`. On the Gemini Developer API a
  `SafetySetting` with a `method` is refused before sending (`unsupported`).
- **Thinking.** `ThinkingConfig.withThinkingBudget` or `withThinkingLevel`. With `includeThoughts: true`, thought parts
  have `isThought == true` and `response.thoughtSummary` joins them. Thought signatures are kept on parts and written
  back by `toJson()`.
- **Tools.** `Tool.googleSearch()`, `Tool.codeExecution()`, `Tool.urlContext()` and `Tool.googleMaps()` are passed
  through. Grounding data is in `candidate.groundingMetadata`, URL context in `candidate.urlContextMetadata`, code
  execution in `ExecutableCodePart` and `CodeExecutionResultPart`.

## Timeouts and cancel

```dart
import 'dart:async';

final Completer<void> stop = Completer<void>();
final Future<GenerateContentResponse> pending = model.generateContent(
  <Content>[Content.text('Write a long essay.')],
  timeout: const Duration(seconds: 30),
  abortTrigger: stop.future,
);
stop.complete();
try {
  await pending;
} on FirebaseAIException catch (e) {
  print('${e.code}, local: ${e.httpStatus == null}');
}
```

- **The call's deadline** is `requestTimeout` (180 seconds, set on `generativeModel`) or the call's `timeout`, which
  replaces it for one call and, for a stream, `streamIdleTimeout` as well. It starts at the call and covers the wait
  for tokens and, in a chat, the time spent waiting in the queue. A unary call's deadline lasts until the whole body
  is read; a stream's lasts until the response headers arrive, then the idle bounds apply. A negative `timeout` is an
  `ArgumentError`.
- **`abortTrigger`** is a future; when it completes, the request is aborted and the call fails with `cancelled`
  (a stream emits `cancelled` and closes). A trigger that completes with an error counts as an abort.
- **An abort stops this client's work only.** The service may still finish the request and bill it.
- `httpStatus == null` tells a local `deadline-exceeded` or `cancelled` from the same code answered by the server.

## Your own HTTP client

`httpClient:` on either constructor replaces the default client (`dart:io` on the VM, fetch in a browser). The client
you give:

- must support `Abortable` requests. A client that cannot abort still makes a call fail locally on time, but the
  request runs on at the service and is billed;
- must not retry. A retrying wrapper such as `RetryClient` bills a generation twice;
- must not follow redirects. A redirect is never followed whatever the client does: the call fails with
  `unavailable`.

The instance does not close a client you gave it.

## Errors

```dart
try {
  await model.generateContent(<Content>[Content.text('Hello')]);
} on FirebaseAIException catch (e) {
  print('${e.code}: ${e.message}');
  print('status ${e.httpStatus}, server ${e.serverStatus}, reason ${e.reason}');
  if (e.code == 'resource-exhausted') {
    print('retry after ${e.retryAfter}');
  }
}
```

`FirebaseAIException` extends `FirebaseException` (plugin `firebase_ai`), with the class name FlutterFire uses.

| Code | When |
|---|---|
| `api-not-enabled` | a 403 whose details say the AI Logic service is disabled for the project; the message names the console page |
| a canonical code (`invalid-argument`, `failed-precondition`, `out-of-range`, `unauthenticated`, `permission-denied`, `not-found`, `aborted`, `already-exists`, `resource-exhausted`, `cancelled`, `deadline-exceeded`, `unimplemented`, `internal`, `unavailable`, `data-loss`, `unknown`) | any other non-2xx answer; the code comes from the envelope's `status` when it is a known name, else from the HTTP status |
| `unauthenticated`, `failed-precondition`, `unavailable` | the Auth provider failed, answered too late, or gave a token over the limit (see "App Check and Auth") |
| `deadline-exceeded` | the call's deadline passed, also during the token wait; for a stream, an idle bound |
| `unavailable` | a transport failure, or any 3xx answer |
| `cancelled` | the call's `abortTrigger` completed |
| `parse-failed` | a success body or stream event that is not a JSON object, invalid UTF-8, nesting over 128 levels, or a body that ends inside an event |
| `response-too-large` | a success body, stream event or stream over its cap |
| `response-error` | thrown by a response accessor for a blocked prompt or candidate |
| `unsupported` | a request field the Developer API rejects (`SafetySetting.method`) |
| `ai-closed` | after `close()`, or for a request in flight when it ran |

`firebaseAIExceptionCodes` lists every code. The fields:

- `httpStatus` is null when the failure happened in the client.
- `serverStatus` and `serverMessage` come from the server's error envelope; the message is sanitized and cut to 1 KiB.
- `reason` is the `reason` of the first `google.rpc.ErrorInfo` detail, for example `API_KEY_INVALID`. **No code is
  derived from message text**, so a rewording by the service never changes a code. Key your handling on `code` and
  `reason`. A `SERVICE_DISABLED` answer for another service is `permission-denied` with `reason` set.
- `retryAfter` is the delay the server asked for (the `retryDelay` of a `RetryInfo` detail, else a `Retry-After`
  header in seconds), clamped to 24 hours, or null. The client never waits on it and never retries.
- `response` holds the response for `response-error` and the aggregate so far for a stream that failed after chunks.
- For Agent Platform, a 404 whose body is not JSON adds the hint "check the location".

An error body over 64 KiB is cut; the call still fails with the status's code. A message never contains a token, the
API key, a request body, a prompt or a URL with a query.

## Limits

- Response caps (decompressed): 64 MiB for a `generateContent` success body, 1 MiB for `countTokens`, 64 KiB for an
  error body (cut), 64 MiB for one stream event and 256 MiB for one stream. Past a success cap the call fails with
  `response-too-large`. The largest answer the request types can ask for is an image at `imageSize: '4K'`; its real
  size is not measured yet.
- JSON nested deeper than 128 levels in any success body fails with `parse-failed`.
- A chat send waits for the previous send of the same session. A paused chat stream keeps its place.
- Chat history lives in memory only.
- Request size: the client sends what you give it.
- There are no automatic retries.
- An API key restricted to Android or iOS apps is refused from desktop, server and web.
- Live on the web will not be able to send App Check or Auth tokens (0.2.0).

## Security

- **The API key is public.** It ships in every app and can be extracted. Without App Check enforcement, anyone who
  holds the key can run paid Gemini calls on your project, up to its quota.
- **App Check is what limits that.** Turn on enforcement for AI Logic and give the app a provider whose tokens come
  from something you control. A debug token passes App Check for the whole project: never ship one.
- **A server that uses one identity** (one key, one App Check identity, one Auth identity) looks like a single caller,
  so per-user quotas collapse into one and one user can exhaust everyone's quota. Where users exist, pass per-user
  Auth tokens.
- **The client talks to one origin**, refuses redirects and refuses an answer from another origin. The origin is fixed
  at construction.
- **Nothing sensitive is logged or thrown.** Tokens, the API key, request bodies, prompts, response text and function
  arguments appear in no log line and no exception message.

## Coming from FlutterFire

`package:firebase_ai` of FlutterFire and this package share their class names and call shapes on purpose, so most call
sites compile after a change of import. What an app meets:

- the import, and construction with `app:` and no `Firebase.app()` default;
- no static instance cache: two `FirebaseAI.googleAI(app:)` calls give two instances;
- `close()`;
- `JsonSchema` instead of `JSONSchema`;
- an exception on every non-2xx answer, where FlutterFire decoded 4xx bodies as responses;
- the accessors' wider throwing set: 16 finish reasons on four accessors, where FlutterFire's `text` throws for
  `SAFETY` and `RECITATION` only;
- no default model name;
- blocked replies are not added to the chat history;
- a `timeout` and an `abortTrigger` on every call;
- no aggregate API for a stream, so an app keeps the chunks itself;
- automatic function calling arrives in 0.2.0.

Whether FlutterFire's own `firebase_ai` runs on Linux with the Dart core through the shim was being checked when this
guide was written; the outcome is recorded in [ai_logic_decisions.md](../ai_logic_decisions.md).

## Web

Requests go through `package:http`'s `BrowserClient` (fetch with a streamed body), so stream chunks arrive as they are
produced. The browser sends the headers the JavaScript SDK sends: `x-goog-api-key`, `x-goog-api-client`,
`X-Firebase-AppId`, `X-Firebase-AppCheck` and `Authorization`. Allow `https://firebasevertexai.googleapis.com` in the
`connect-src` of your Content-Security-Policy. The runtime part of `x-goog-api-client` is `web` in a browser.

The web example [examples/ai_web](../../examples/ai_web/README.md) streams an answer into a page and has a Stop button
that uses `abortTrigger`. It is in the web gallery.

## Examples and tests

The seven programs in [firebase_ai/firebase_ai_dart/example](../../firebase_ai/firebase_ai_dart/example/README.md) cover
generate, stream, chat, function calling, structured output and cancel. They call your project and are billed to it.

The package's tests use `MockClient` and a fake server, `tool/ai_fake_server.dart`, which answers canned replies,
streams and errors on loopback. The CI job "AI Logic tests in Chrome" runs the same test tree in a browser with dart2js
and dart2wasm. For your own code, an injected `httpClient` (a `MockClient`) is the way to test without a network.
