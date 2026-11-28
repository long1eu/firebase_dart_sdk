# App Check production verification kit

There is no App Check emulator, so the unit tests of `firebase_app_check_dart` use a scripted `http.Client` and send
nothing to Google. This kit runs the client against a **real** Firebase project and prints, for each of six checks,
`PASS`, `FAIL`, `INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It answers what the unit tests cannot: that
the real exchange endpoint accepts the request the client sends (snake_case body, API key in the `X-Goog-Api-Key`
header, host `firebaseappcheck.googleapis.com`), that a token is cached, forced and limited-use as designed, and that
a refused debug token ends in the documented errors.

The code is `firebase_app_check/firebase_app_check_dart/tool/verify_production.dart`; `run.sh` here runs it from the
right directory. It is the same kind of kit as `tool/verify_production_remote_config`.

## Before you run it

1. Use a project you can spare, with a registered app (project settings, "Your apps"). It gives you the **project id**,
   the **app id** (`1:<project number>:web:<hash>`) and the **API key**. Use an API key without application
   restrictions: a desktop program sends no package name, certificate or bundle id.
2. Create a debug token for that app: Firebase console, App Check, Apps, the app's menu, "Manage debug tokens", "Add
   debug token". The console accepts a token you supply, so you can create it yourself with a UUID tool; a fresh
   token is best. **A debug token is a secret**: whoever holds it gets App Check tokens for that app until the token
   is deleted.
3. Put the debug token in the environment variable `FIREBASE_APPCHECK_DEBUG_TOKEN`. The kit reads it from nowhere
   else: a command-line argument would be visible to other users in the process list. The kit never prints it.
4. Do not turn enforcement on for this test. The kit asks for tokens only; it calls no Firebase product.

## What it does to your project

- It sends a handful of requests to the App Check exchange endpoint of that project: one session token, one forced
  refresh, one limited-use token, one request with a second, unregistered random debug token (which is refused by
  design), and one more inside the gate window, which the client itself refuses without sending anything. The
  refused exchange may show up in the App Check metrics of the project.
- It stores the session token, in check 5, in a new private temporary directory (a `FileKeyValueStore`) and removes
  the directory at the end, also after Ctrl-C. If that fails it names the directory to remove by hand.
- It never prints the API key, the debug token or an App Check token. It prints the project id and the app id first,
  token lengths and lifetimes, and the status of the refused exchange.
- Against the real project it does nothing without `--yes`: without it, it prints the plan and exits 2.

## Commands

From the repository root (the folder that holds `tool/` and `firebase_app_check/`):

    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_APP_ID=1:123456789:web:abc123
    export FIREBASE_API_KEY=...                                  # or --api-key=
    export FIREBASE_APPCHECK_DEBUG_TOKEN=...                     # the secret; only from the environment

    tool/verify_production_app_check/run.sh                      # prints the plan, does nothing
    tool/verify_production_app_check/run.sh --yes                # runs the checks

Options: `--project-id`, `--app-id`, `--api-key` (instead of the variables), `--yes`, `--help`.

Save the report: `... --yes | tee verify_app_check_report.txt`. It holds the project id and the app id, and no
credentials.

**Afterwards, delete the debug token in the console** (App Check, Apps, Manage debug tokens).

Check 3 waits 31 seconds (the forced-refresh floor is 30 seconds), so a run takes about a minute.

## The checks and how to read them

| id | check | what a result means |
| --- | --- | --- |
| 1 | exchange a session token | `getToken()` exchanges the debug token and returns a token; the line shows the `ttl` the server gave and the token's length. `FAIL` carries the error code and the HTTP status (`fetch-status-error` with 400 or 403: look at the app id, the API key's restrictions and whether the debug token is registered). |
| 2 | cached token | A second `getToken()` sends no request: the cache answers. |
| 3 | forced refresh | After 31 seconds, `getToken(forceRefresh: true)` exchanges again and returns a different token. |
| 4 | limited-use token | `getLimitedUseToken()` is accepted with `limited_use: true`; the line shows its `ttl`. |
| 5 | second instance, same file store | After the first instance is closed, a second one on the same `FileKeyValueStore` answers `getToken()` from the stored record without a request. |
| 6 | refused debug token and the gate | An unregistered random UUID gives `fetch-status-error`; the line shows the status, the `serverStatus` and whether `serverMessage` contained `<redacted>` (the client replaces the debug token in the server's text). A second call inside the window gives `throttled`. |

A check that needs an earlier one that did not pass is `SKIPPED`.

Exit code: 0 when no check failed, 1 when one is `FAIL`, 2 for a missing option or a missing `--yes`, 64 for an
unknown option, 130 after Ctrl-C.

What to send back: the whole report, to the maintainer who asked you to run the kit.

## Not verified

- A restricted API key (an Android or iOS application restriction): the client sends none of the identity headers.
- A browser: the exchange from a web page, including the preflight, is not part of this kit.
- Quota or price of the endpoint, and the metrics the console shows for tokens and refused requests.
