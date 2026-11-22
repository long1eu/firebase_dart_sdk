# rtdb_presence_worker

| | |
| --- | --- |
| Product | Firebase Realtime Database |
| Platform | Dart VM on a server or a desktop (Linux, macOS, Windows); no Flutter |
| Backend | Realtime Database emulator (project `demo-example`; start it from the repository root with `tool/start_database_emulator.sh` (port 9100)), or a real database by URL |
| Run | `FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run bin/presence_worker.dart --id worker-a` |
| CI | none; run by hand against the emulator |
| Web gallery | - |

A long-running process that keeps `status/<id>` in the Realtime Database true: `online` while
it is connected, `offline` when the link drops or it stops. A second mode lists who is online.

| Command | What it does |
| --- | --- |
| `dart run bin/presence_worker.dart [worker] [--id x]` | Keeps the record of worker `x` until `SIGINT` or `SIGTERM`. |
| `dart run bin/presence_worker.dart watch` | Prints the workers whose `state` is `online`, with the age of their heartbeat, on every change. |

The record is `status/<id> = {state, lastChanged, heartbeat}`; the last two are server times.

## The order of the steps

On every `.info/connected == true` (`FirebaseDatabase.onConnected`):

1. `onDisconnect.update({state: offline, lastChanged: <server time>})`, and wait for the answer.
2. Only then `update({state: online, lastChanged, heartbeat})`.

Why: if `online` were written first and the link dropped before the onDisconnect was registered,
nothing would ever write `offline`. A registration also lives in the server's session, so a new
connection starts without one; it must be made again at every connect. When the registration
fails with `disconnected` (the link dropped before the server answered), `online` is not
written and the next connect starts the sequence again. Any other failure (for example
`permission-denied`) stops the worker with exit code `1`.

A timer writes `heartbeat` every 10 s (`--heartbeat`) while the worker is online, so a watcher
can tell a live worker from a record whose process was killed without the link being noticed.

Stop on `SIGINT` or `SIGTERM`: write `offline`, cancel the onDisconnect, close the database,
each step with a 5 s timeout. Exit codes: `0` clean, `1` a step was not acknowledged or the
rules refused the worker, `64` bad arguments, `78` no backend configured.

## Configuration

| Setting | Meaning |
| --- | --- |
| `FIREBASE_DATABASE_EMULATOR_HOST` or `--emulator-host` | `host:port` of the emulator. Required unless a database URL is given. |
| `FIREBASE_DATABASE_URL` or `--database-url` | A database URL; its namespace is used with the emulator too. |
| `WORKER_ID` or `--id` | The id in `status/<id>` (default `<host>-<pid>`). |
| `FIREBASE_API_KEY` | Optional Web API key. |

The project is `demo-example`. For `watch` on a real database add `".indexOn": "state"` at
`status` in the rules, or the client downloads the whole list and filters it itself.

## Status

Run by hand against the Database emulator: a worker goes online, a watcher sees it, and after the
worker is killed with `SIGKILL` the watcher sees it leave, from the server's `onDisconnect` write.
No tests.
