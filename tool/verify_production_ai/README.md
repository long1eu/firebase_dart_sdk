# Firebase AI Logic production verification kit

`firebase_ai_dart` has no emulator to test against: the Firebase CLI has none for AI Logic. This kit sends real
requests to Firebase AI Logic for a **real** project and prints, for each check, `PASS`, `FAIL`, `INCONCLUSIVE` or
`SKIPPED` with a one-line explanation and, where the check records facts, indented lines with them. It answers what
the unit tests cannot: that the proxy accepts the requests the client sends, what its streams look like byte for
byte, and which errors it gives.

**Every check costs money.** Each one runs at least one paid Gemini request on the project; K11 sends very large
requests. Run the kit only with the project owner's approval for that run.

The code is `firebase_ai/firebase_ai_dart/tool/verify_production.dart`; `run.sh` here runs it from the right
directory. It is modelled on the Remote Config kit (`tool/verify_production_remote_config`).

## Before you run it

1. Use a project with Firebase AI Logic enabled for the backend you check: the Gemini Developer API, Agent Platform
   (Vertex AI), or both (Firebase console, AI Logic).
2. Register a web app in the project (project settings, "Your apps"). It gives you the **app id** and the
   **API key**. Use a key without application restrictions, or one whose API restrictions allow the Firebase AI Logic
   API. The client sends no package name, certificate or bundle id, so a key restricted to Android or iOS apps is
   refused.
3. Choose a **model** that the backend serves, for example a current Gemini Flash model. There is no default.
4. The project must not enforce App Check for AI Logic, except for K9 (below).

Optional checks need more:

| Check | Needs |
| --- | --- |
| K7, third case | a second project whose Gemini Developer API is **not** set up in AI Logic: `--unconfigured-project-id=<id>` and its API key in `FIREBASE_AI_UNCONFIGURED_API_KEY` |
| K9 | the owner turns App Check enforcement on for AI Logic before the run and off after it, then passes `--app-check-enforced`. For the "consumed token" case, a limited-use App Check token that was already used once, in `FIREBASE_AI_CONSUMED_APP_CHECK_TOKEN` |
| K10 | an ID token of a test user, fetched and then revoked (revoke the user's refresh tokens or disable the user) before the run, in `FIREBASE_AI_REVOKED_ID_TOKEN` |
| K11 | `--large-requests`: a 21 MiB inline request and a history of about 1.2 million tokens. Expensive if the server accepts them |
| K12 | `--image-model=<model>`: a model that answers images. It asks for one 4K image |

## What it does to your project

- It sends generate, stream and count requests to the models named, as the app given. It changes nothing in the
  project.
- It never prints the API key or a token. It prints the project id, the app id, model names, HTTP statuses,
  `error.status`, ErrorInfo `reason` and `domain`, and server messages cut to 160 characters (K7).
- Against the real project it sends nothing without `--yes`: without it, it prints the plan and exits 2.

## Commands

From the repository root (the folder that holds `tool/` and `firebase_ai/`):

    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_APP_ID=1:123456789:web:abc123
    export FIREBASE_API_KEY=...                                  # or --api-key=

    tool/verify_production_ai/run.sh --model=gemini-x                  # prints the plan, sends nothing
    tool/verify_production_ai/run.sh --yes --model=gemini-x            # Gemini Developer API
    tool/verify_production_ai/run.sh --yes --model=gemini-x --backend=agent-platform --location=us-central1
    tool/verify_production_ai/run.sh --yes --model=gemini-x --backend=google-ai --backend=agent-platform

Options: `--project-id`, `--app-id`, `--api-key` (instead of the variables), `--model` (required),
`--backend google-ai|agent-platform` (default `google-ai`; give it twice for both), `--location` (default `global`,
used only with `agent-platform`), `--image-model`, `--unconfigured-project-id`, `--app-check-enforced`,
`--large-requests`, `--yes`, `--help`.

Save the report: `... --yes | tee verify_ai_report.txt`. It holds the project id and the app id, and no credentials.

Exit code: 0 when no check failed, 1 when one is `FAIL`, 2 for a missing option or a missing `--yes`, 64 for an
unknown option.

## The checks and how to read them

The checks run in this order for each backend. K8 (a browser CORS check) does not exist: the kit is a VM program.

| id | check | what a result means |
| --- | --- | --- |
| K1 | generateContent | `generateContent` with `maxOutputTokens: 10` answers with a candidate. The indented lines record whether a `fileUri` with `gs://`, `https://` and YouTube was accepted (open item O5); they never fail the check. |
| K2 | stream bytes | A plain `?alt=sse` request: the escaped bytes of the first event (line ends and `data:` spacing), the number of events and how many carried `promptFeedback` without candidates. Then the client streams the same prompt. `INCONCLUSIVE` when the answer had fewer than two events. |
| K3 | countTokens | The backend's count body of the specification (§3.4) with and without a system instruction; `PASS` when the instruction is counted. |
| K4 | stream timing with thinking | A plain stream with a thinking budget: time to headers, to the first event, the longest gap between events and the SSE comment lines. These set `streamIdleTimeout` (180 s by default). |
| K5 | two-turn chat | Two sends; `PASS` when the history then has four entries. |
| K6 | structured output | `responseSchema` (upper-case types) and `responseJsonSchema`; `PASS` when both answers are the requested JSON object. |
| K7 | error answers | An unknown model must give `not-found` from the server. The indented lines record the code, status and `reason` for it, for an invalid API key, and (optional) for a project whose Developer API is not configured, with `domain` (open item O6). |
| K9 | App Check enforcement | With enforcement on: a request with no token, with the placeholder token and (optional) with a consumed limited-use token. `PASS` when all are refused; `INCONCLUSIVE` when one was accepted (enforcement can take minutes to apply). |
| K10 | revoked ID token | A request with the revoked token. `PASS` when refused without `usageMetadata`; `FAIL` when the refusal carries `usageMetadata` (billed work before a 401); `INCONCLUSIVE` when accepted. |
| K11 | size and context limits | The answers to a 21 MiB inline request and to a history over the context window (open items O4 and O11). `FAIL` only when the client failed locally instead of reporting the server's answer. |
| K12 | 4K image size | The body size of a 4K image answer (open item O10). `FAIL` when it is over the client's 64 MiB cap. |
| K13 | client version header | The same request with `x-goog-api-client: ... fire/3.1.0` (the JS SDK's) and with this package's version. `FAIL` when the statuses differ (open item O9). |
| K14 | safety method on the Developer API | A plain request with `safetySettings[].method`, which the client refuses locally (`unsupported`). `PASS` when the server refuses it too; `FAIL` when the server accepts it, which means the client refusal should be removed. Skipped on Agent Platform. |

A check that needs an option that was not given is `SKIPPED`.

What to send back: the whole report, to the maintainer who asked you to run the kit.

## Not verified

- Anything on the web: the browser tests run against a local server (`tool/test_browser_ai.sh`), and
  `examples/ai_web` is a page you can open by hand.
- Limited-use App Check tokens minted by a real provider, and Auth tokens of a signed-in user, through the client:
  the kit sends tokens only in plain requests (K9, K10).
- Live (WebSocket), server prompt templates and automatic function calling: they are not in 0.1.0.
