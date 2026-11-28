# firebase_ai_dart

Unofficial pure-Dart client of Firebase AI Logic: Gemini models called through Firebase, with App Check and
Firebase Auth tokens, on the Dart VM (macOS, Windows, Linux, servers, command-line tools) and the web (dart2js
and dart2wasm). It talks to the Firebase AI Logic REST API and the server-sent-event stream of the same API. It
is not a port of a Firebase SDK; its protocol follows the Firebase JavaScript SDK.

Start with `FirebaseAI.googleAI` (the Gemini Developer API) or `FirebaseAI.agentPlatform` (Agent Platform, with
a location).

## Status

0.1.0, first release, not published yet. There is no emulator for AI Logic; the tests use a fake server and
`MockClient`. The client has not run against a production project yet: the production verification kit
(`tool/verify_production_ai/`) runs it against one, and every check costs money.

Not in 0.1.0: Live (WebSocket), server prompt templates, automatic function calling, Imagen, on-device
inference, cached content, microphone and speaker helpers, and a FlutterFire adapter. Live, templates and
automatic function calling are planned for 0.2.0.

## Install

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

`_firebase_transport_dart` is an internal package of this repository (the token rule, the capped send and the
stream decoder shared by the products); application code does not import it. Once the packages are published,
`dart pub add firebase_ai_dart firebase_app_dart` does the same, and the override goes away.

## Set up

Firebase AI Logic has to be turned on for your project (Firebase console, AI Logic), with the backend you use set
up. The app options come from a web app (or any app) registered in the project; the console has no desktop app
type, so desktop and server programs use the same options.

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

- The constructors send nothing. Two calls give two independent instances: there is no instance cache.
- `model` is required and has no default, because model names change between releases. A name is letters,
  digits, `.`, `_` and `-`; a leading `models/` is accepted and removed.
- For Agent Platform use `FirebaseAI.agentPlatform(app: app, location: 'us-central1')`. The location defaults to
  `global`.
- A missing or empty API key, app id or project id is a `StateError` at the first call that needs it, not at
  construction.
- `ai.close()` aborts the requests in flight (they fail with `ai-closed`), closes the HTTP client if the
  instance created it, and makes later calls fail with `ai-closed`. It runs by itself when the app is deleted.

### App Check and Auth

The instance reads `app.appCheckProvider` and `app.authProvider` at every request, so a provider set later is
used from the next request. An Auth token goes out as `Authorization: Firebase <ID token>`, an App Check token as
`X-Firebase-AppCheck`. Without a provider the header is left out, and the instance logs one `info` line at its
first request (when you pass a `logger`): with App Check enforced for AI Logic such requests are refused.

A pure-Dart program has no device attestation of its own. These packages do not attest a device: you supply the
tokens. The sources a program can use:

- the App Check client of this repository, with a debug provider on machines you control, or a custom provider
  (reCAPTCHA on the web);
- an `AppCheckTokenProvider` you write, that asks your own server for a token;
- for limited-use tokens (`useLimitedUseAppCheckTokens: true`), a provider that also implements
  `LimitedUseAppCheckTokenProvider` and asks your server for one token per request.

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

A debug token passes App Check for the whole project. Use one only on machines you control, never inside a
binary you ship: a distributed app uses a custom provider backed by your own server.

When a token cannot be had, the call is not failed by the client: a failed limited-use mint sends the placeholder
token, and a provider that cannot mint limited-use tokens sends no App Check header. Whether the service then
refuses the request depends on your project's App Check enforcement. An Auth token that cannot be had fails the
call (`unauthenticated`, or `unavailable` when the provider does not answer in time).

### Keys per platform

An API key restricted to Android or iOS apps is refused from desktop, server and web. Use one key per platform,
restricted to the Firebase AI Logic API, with HTTP referrer restrictions on the web. The client sends no
`X-Android-Package`, `X-Android-Cert` or `X-Ios-Bundle-Identifier`: a value typed by a desktop, server or web
build would be a false claim to the key restriction.

`X-Firebase-AppId` is sent only while `app.isAutomaticDataCollectionEnabled` is true, checked at each request.

## Generate

```dart
final GenerateContentResponse response = await model.generateContent(
  <Content>[Content.text('Write a haiku about Dart.')],
);
print(response.text);
print(response.usageMetadata?.totalTokenCount);
```

`generateContent` returns the response. A blocked prompt or a blocked answer is not an exception on receipt:
`response.text`, `thoughtSummary`, `inlineDataParts` and `functionCalls` throw a `FirebaseAIException` with the
code `response-error` when the prompt was blocked (`promptFeedback.blockReason`) or the first candidate ended
with a blocking finish reason (`SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`, `SPII`,
`MALFORMED_FUNCTION_CALL`, the image reasons, `NO_IMAGE`, `LANGUAGE`, `UNEXPECTED_TOOL_CALL`,
`TOO_MANY_TOOL_CALLS`, `MISSING_THOUGHT_SIGNATURE` and `MALFORMED_RESPONSE`). `MAX_TOKENS`, `OTHER` and `STOP`
never throw: the answer is partial but usable and was billed. To react to a cut-off answer, read
`response.candidates.first.finishReason`. Only the first candidate is examined; the others are in `candidates`.

Settings of a model (`safetySettings`, `generationConfig`, `tools`, `toolConfig`, `systemInstruction`) can be
given per call; a per-call value replaces the model's value instead of merging with it.

```dart
final GenerativeModel concise = ai.generativeModel(
  model: '<a model name>',
  systemInstruction: Content.system('Answer in one short paragraph.'),
  generationConfig: const GenerationConfig(temperature: 0.4, maxOutputTokens: 400),
);
final CountTokensResponse count = await concise.countTokens(
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

Nothing is sent until the stream is listened to. Every event that decodes is emitted, including events that carry
only `usageMetadata` or `promptFeedback`; a chunk without text has `text == null`. A stream that fails after some
chunks ends with an exception whose `response` holds what arrived, so a billed partial answer is not lost.
Cancelling the subscription aborts the request and is not an error.

A stream ends with `deadline-exceeded` when no bytes arrive for `streamIdleTimeout` (180 seconds by default), and
also when no event arrives for that long: keep-alive comment lines do not count as events. `streamIdleTimeout:
null` turns both bounds off; then only the call's `timeout` before the headers and the `abortTrigger` remain.

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
print(chat.history.length); // 4: two entries per successful turn
```

- **History rule.** A message and its reply are added to `history` together, only when the first candidate has
  parts and does not end with a blocking finish reason. After an exception, a cancel, a timeout, a blocked prompt,
  an empty candidate or a blocking finish reason, the history is unchanged. Replies that end with `MAX_TOKENS` or
  `OTHER` are added. This is one rule for `sendMessage` and `sendMessageStream`.
- **Sends are serialized.** A send starts only after the previous one finished. `sendMessageStream` takes its
  place in the queue when the stream is listened to; a stream that is never listened to blocks nothing. A paused
  subscription keeps its place and stops both idle timers: cancel a chat stream the app no longer reads instead of
  pausing it.
- **Starting from a history.** `startChat(history: ...)` checks that the first content has the role `user`, that
  roles alternate, and that no content is empty; a failure is an `ArgumentError` naming the index. `history` is
  plain data with `toJson` and `Content.fromJson`, so an app can store it: chat history lives in memory only.
- **Cost.** Each turn resends the whole history, so the input tokens of a conversation grow roughly with the square
  of the number of turns. A `countTokens` call before every turn adds a request against the same quota, and with
  limited-use App Check each send also costs one token mint on your server. Cap the turns, or summarize older
  turns into one message and start a new session from that history, and call `countTokens` only when the history
  has grown.
- **Trimming.** The client keeps every turn and never trims. To check the size, call `countTokens(chat.history)`
  on a model created with the chat's settings, and start a new session from a shortened history.
- **Media.** Image and audio replies are kept in the history and re-encoded on every later turn. Drop media turns
  from a history you keep if you do not need them.

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

Inline data goes into the request as base64 and is held in memory about 3.7 times over while the request runs: a
20 MB image takes about 75 MB. For large media, use file URIs (`FileData(mimeType, fileUri)`) that the service can
read. Which URI schemes a backend accepts, and the size limit for inline data, are not settled yet; the kit checks
them.

## Function calling

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
);
final ChatSession toolChat = withTools.startChat();
final GenerateContentResponse asked = await toolChat.sendMessage(
  Content.text('What is the weather in Cluj-Napoca?'),
);
for (final FunctionCall call in asked.functionCalls) {
  final GenerateContentResponse answered = await toolChat.sendMessage(
    Content.functionResponse(call.name, <String, Object?>{'sky': 'clear'}, id: call.id),
  );
  print(answered.text);
}
```

Function calling is manual: the program runs the function and sends a function response. Automatic function
calling arrives in 0.2.0. Send the model's reply back with its thought signatures: a model reply that loses its
signature can end with `MISSING_THOUGHT_SIGNATURE`; the chat session keeps replies as received.

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
      },
    ),
  ),
);
```

`responseSchema` takes a `Schema` (an OpenAPI subset); `responseJsonSchema` takes a `JsonSchema` that is sent
as given. A schema shapes the answer, but the program still checks what it decodes.

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

- **Safety.** Ratings are in each candidate's `safetyRatings`. On the Gemini Developer API a `SafetySetting` with a
  `method` is refused before sending (`unsupported`).
- **Thinking.** `ThinkingConfig` sets a budget or a level. Thought parts have `isThought == true`;
  `response.thoughtSummary` joins them.
- **Tools.** `Tool.googleSearch()`, `Tool.codeExecution()`, `Tool.urlContext()` and `Tool.googleMaps()` are passed
  through. Grounding data is in `candidate.groundingMetadata`.
- **Other output.** Image and audio output fields (`responseModalities`, `speechConfig`, `imageConfig`) are passed
  through. An image answer can be several MB; the response caps are in "Limits".

## Timeouts and cancel

Every call takes a `timeout` and an `abortTrigger`:

```dart
import 'dart:async';

final Completer<void> stop = Completer<void>();
final Future<GenerateContentResponse> pending = model.generateContent(
  <Content>[Content.text('Write a long essay.')],
  timeout: const Duration(seconds: 30),
  abortTrigger: stop.future,
);
// Later, for example from a button:
stop.complete();
try {
  await pending;
} on FirebaseAIException catch (e) {
  print(e.code); // cancelled
}
```

- The default deadline is `requestTimeout` (180 seconds, set on `generativeModel`); `timeout` replaces it for one
  call, and for a stream also replaces `streamIdleTimeout`. The deadline starts at the call and covers the wait
  for tokens. For a unary call it lasts until the whole body is read; for a stream, until the response headers
  arrive, and then the idle bounds apply.
- `abortTrigger` completing aborts the request: the call fails with `cancelled`. **An abort stops this client's
  work only.** The service may still finish the request and bill it.
- Every deadline counts from the call, including the time a chat send waits in its queue.

## Your own HTTP client

`FirebaseAI.googleAI(app: app, httpClient: client)` uses `client` for every request. The client you pass:

- must support `Abortable` requests. One that cannot abort still makes a call fail locally on time, but the
  request runs on and is billed;
- must not retry. A retrying wrapper such as `RetryClient` bills a generation twice;
- must not follow redirects. Redirects are refused whatever the client does: a 3xx answer is `unavailable`.

The instance does not close a client you pass.

## Errors

Every non-2xx answer is a `FirebaseAIException` (`on FirebaseAIException` is the same class name as in
FlutterFire). It has:

- `code`: `api-not-enabled` (the AI Logic service is not enabled for the project; the message names the console
  page), a canonical code from the server's status (`invalid-argument`, `permission-denied`, `not-found`,
  `resource-exhausted`, `unavailable` and so on), or one of the client's codes: `unauthenticated`,
  `failed-precondition`, `deadline-exceeded`, `cancelled`, `parse-failed`, `response-too-large`, `response-error`,
  `unsupported` and `ai-closed`. `firebaseAIExceptionCodes` lists them all;
- `httpStatus`: the HTTP status, or null when the failure happened in the client. That is how you tell a local
  `deadline-exceeded` or `cancelled` from the same code answered by the server;
- `serverStatus` and `serverMessage`: the status name and the text of the server's error (sanitized, at most
  1 KiB);
- `reason`: the machine-readable cause from the server's error details, for example `API_KEY_INVALID`. No code is
  derived from message text, so key your handling on `code` and `reason`, not on `message`;
- `retryAfter`: the delay the server asked for, from `RetryInfo` or a `Retry-After` header, clamped to 24 hours.
  The client never waits on it and never retries;
- `response`: for `response-error`, and for a stream that failed after some chunks, the response so far.

A message never contains a token, the API key, a request body, a prompt or a URL with a query.

## Limits

- Response caps (decompressed): 64 MiB for a `generateContent` body, 1 MiB for `countTokens`, 64 KiB for an error
  body (cut, the status's code is kept), 64 MiB for one stream event and 256 MiB for one stream. Past a success cap
  the call fails with `response-too-large`.
- JSON nested deeper than 128 levels fails with `parse-failed`.
- A chat send waits for the previous send of the same session.
- Chat history lives in memory only, and is not trimmed.
- Request size: the client sends what you give it. The service's limit for inline data is not settled yet.
- There are no automatic retries; a retried generation is billed again.
- Live on the web will not be able to send App Check or Auth tokens (0.2.0).

## Security

- **The API key is public.** It ships in every app and can be extracted. Without App Check enforcement, anyone who
  holds the key can run paid Gemini calls on your project, up to its quota.
- **App Check is what limits that.** Turn on enforcement for AI Logic in the project, and give the app a provider
  that gets its tokens from something you control (see "App Check and Auth").
- **Per-user quotas.** A server that calls AI Logic with one key, one App Check identity and one Auth identity looks
  like a single caller, so per-user quotas collapse into one. Where users exist, pass per-user Auth tokens.
- **Logs.** The `logger` receives no token, API key, request body, prompt, response text or function argument.
- **Redirects and hosts.** The client talks to one origin, refuses redirects and refuses answers from another origin.

## Coming from FlutterFire

The names follow the `firebase_ai` plugin of FlutterFire, so most call sites are unchanged. What differs:

- the import, and construction with `app:` and no `Firebase.app()` default;
- no instance cache, and a `close()`;
- `JsonSchema` instead of `JSONSchema`;
- an exception on every non-2xx answer;
- the accessors throw for more finish reasons;
- no default model name;
- blocked replies are not added to the chat history;
- a `timeout` and an `abortTrigger` on every call;
- no public aggregate of a stream: keep the chunks yourself;
- automatic function calling arrives in 0.2.0.

The guide has the details: [docs/guides/ai_logic.md](../../docs/guides/ai_logic.md).

## Web

Requests go through `package:http`'s `BrowserClient` (fetch with a streamed body), so streams arrive chunk by
chunk. The browser sends the same headers as the JavaScript SDK (`x-goog-api-key`, `x-goog-api-client`,
`X-Firebase-AppId`, `X-Firebase-AppCheck`, `Authorization`), which the JavaScript SDK also sends from a browser. Put
`https://firebasevertexai.googleapis.com` in the `connect-src` of your Content-Security-Policy. The web example
`examples/ai_web` of this repository shows a page that streams an answer and stops it.

## More

- Guide: [docs/guides/ai_logic.md](../../docs/guides/ai_logic.md)
- Parity with the JS, Android, iOS and FlutterFire SDKs: [docs/ai_logic_parity.md](../../docs/ai_logic_parity.md)
- Decisions: [docs/ai_logic_decisions.md](../../docs/ai_logic_decisions.md)
- Examples: [example/](example/)
