# Functions production verification kit

`cloud_functions_dart` was verified against the Functions emulator only. This kit runs named checks of the client
against the fixture functions, on the emulator or on a **real** project, and prints, for each one, `PASS`, `FAIL`,
`INCONCLUSIVE` or `SKIPPED` with a one-line explanation. It answers what the emulator cannot: whether Google's
front end buffers server-sent events or drops their heartbeats, how a real project answers an unknown function,
a CORS preflight and a forged ID token.

The code is `cloud_functions/cloud_functions_dart/tool/verify_production.dart`; `run.sh` here runs it from the
right directory. It is modelled on the Storage kit (`tool/verify_production_storage`).

**Status of the kit itself:** it runs against the Functions emulator, where the result of every check is known; CI
runs that mode. It has not been run against a real project: that needs the fixture functions deployed, which needs
the Blaze plan and the owner's approval. Until it has run there, the README of the package says "verified on the
emulator".

## Modes

### `--backend=emulator`

Needs `FIREBASE_FUNCTIONS_EMULATOR_HOST` (start the emulator with `tool/start_functions_emulator.sh`, which prints
the line to export; install the fixture's packages first with `npm ci --prefix tool/functions_emulator/functions`).
The project is `demo-functions`. The user is an unsigned emulator JWT (`{"alg":"none"}`, `sub` and `user_id`
`kit-user`) handed out by an `AuthTokenProvider` defined in the kit, which the emulator accepts without checking.
There is nothing to confirm with `--yes` and nothing to delete.

    ./tool/start_functions_emulator.sh 9501
    FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1:9501 tool/verify_production_functions/run.sh --backend=emulator
    ./tool/stop_functions_emulator.sh 9501

### `--backend=production`

Requires `--yes`; without it the kit prints what it would do and exits 2. Options: `--project-id`, `--app-id`,
`--api-key` and `--region` (or the variables `FIREBASE_TEST_PROJECT_ID`, `FIREBASE_TEST_APP_ID`,
`FIREBASE_API_KEY`).

The kit signs in a throwaway email user with `FirebaseUserAuth` of `firebase_auth_providers_dart`, which it creates
before the checks and deletes at the end, also after a failed check and on Ctrl-C. The password is random, lives
in memory and is never printed. The kit never prints an ID token, an API key or a refresh token.

The fixture functions must be deployed first, by the owner (they need the Blaze plan):

    firebase deploy --project flutter-sdk \
      --only functions:echo,functions:context,functions:fail,functions:slow,functions:stream,functions:streamHb

The project must allow email and password sign-in. A deployed function bills its invocations; a full run makes a few
dozen short calls and holds a few streams open for up to ten seconds.

## What it does to your project

- It creates one Auth user and deletes it.
- It calls the fixture functions above. They keep nothing.
- It sends one CORS preflight (`OPTIONS`) and one request to a function name that does not exist.
- It never writes data and never changes the project's configuration.

## Checks

| # | Check | Mode |
|---|---|---|
| K1 | `echo` round trip of every value type (null, bool, int, whole and fractional double, string with emoji, nested list and map) | both |
| K2 | `context` sees the signed-in user's uid: `kit-user` in emulator mode, the throwaway user's uid in production | both |
| K3 | `fail` with `already-exists` and with `aborted`: both HTTP 409, the codes come from the body | both |
| K4 | `slow` (5 s) with a 2 s timeout gives `deadline-exceeded` | both |
| K5 | `stream` delivers three messages and the result | both |
| K6 | `streamHb` (a ping every 2 s of silence, a 7 s gap between its two chunks) with a 5 s timeout completes, because each ping restarts the idle timeout; the late chunk arrives between 7 s and 9 s after the first: the front end does not buffer the pings | both |
| K7 | `wrappedInt64` returns 9223372036854775807 exactly (the kit runs on the VM). Emulator only: the fixture builds the map itself, so production would test only the client's decoder | emulator |
| K8 | `wrappedUnknownType` returns its map unchanged. Emulator only, for the same reason | emulator |
| K9 | an unknown function name gives `not-found` (HTTP 404) without a callable body | both |
| K10 | a CORS preflight (`OPTIONS` with `Origin: http://localhost:8080`, `Access-Control-Request-Method: POST` and `Access-Control-Request-Headers: content-type,authorization,x-firebase-appcheck,accept`) is answered 2xx with that origin allowed | both |
| K11 | App Check: always `SKIPPED` in 0.1.0, because it needs an App Check provider that mints limited-use tokens (the App Check package). The check is written when that package exists | production |
| K12 | A forged ID token (the throwaway user's token with its signature bytes changed), sent through an `AuthTokenProvider` the kit defines: the answer's HTTP status and whether it has a callable envelope are printed, and the check is `INCONCLUSIVE`, not `FAIL`, either way. It measures what production does with such a token: an envelope means the client's refresh after a bare 401 never fires there; a bare 401 means it does | production |

How to read a result:

- `PASS`: the client and the server did what the specification says.
- `FAIL`: they did not. Do not publish the client until the cause is known; the line says what differed.
- `INCONCLUSIVE`: the check ran but cannot say yes or no (K12 always, or a project without the preconditions).
- `SKIPPED`: not run in this mode, with the reason.

K5, K6 and K9 to K12 are the ones that measure the production front end. K6 fails when the front end buffers
the event stream until the end, which would make streaming useless there; K10 decides whether a browser page can
call a deployed function at all.

Save the report: `... --yes | tee verify_functions_report.txt`. It holds the project id and the app id, and no
credentials.

Exit code: 0 when no check failed, 1 when one is `FAIL`, 2 for a missing option or a missing `--yes`.
