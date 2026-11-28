# firebase_ai_dart examples

Small command-line programs. There is no emulator for AI Logic, so they talk to the project you name, and every call
is billed to it. Turn on Firebase AI Logic in the project first. If the project enforces App Check for AI Logic,
the calls need a token: give the `FirebaseApp` an App Check provider (see the README of the package); these examples
build the app without one.

```sh
cd firebase_ai/firebase_ai_dart && dart pub get
dart run example/generate.dart --api-key <key> --app-id <app id> --project-id <project id> --model <model name>
```

The model name is required and has no default: model names change between releases. Use `--backend agent-platform`
(and `--location`, default `global`) for the Agent Platform backend. Whatever follows the options is the prompt.

| File | Shows |
|---|---|
| `main.dart` | One answer, with positional arguments (the pub.dev example). |
| `generate.dart` | `generateContent` with a system instruction and a generation configuration, `text`, the finish reason, `usageMetadata` and `countTokens`. |
| `stream.dart` | `generateContentStream`: chunks as they arrive, and the usage of the last one. |
| `chat.dart` | `startChat`, `sendMessage`, `sendMessageStream` and the history. |
| `function_calling.dart` | Manual function calling: a declaration, `functionCalls`, and the result sent back as a function response. |
| `structured_output.dart` | `responseMimeType` and `responseSchema`, and decoding the JSON answer. |
| `cancel.dart` | A per-call `timeout` and an `abortTrigger`. |

`common.dart` parses the options with `package:args` and builds a `FirebaseApp` and a `FirebaseAI`.
