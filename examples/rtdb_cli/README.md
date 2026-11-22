# rtdb_cli

| | |
| --- | --- |
| Product | Firebase Realtime Database |
| Platform | Command line (Dart VM: macOS, Linux, Windows) |
| Backend | The Database emulator; a real database only with an explicit `--database-url` |
| Run | `cd examples/rtdb_cli && dart pub get && dart run rtdb_cli --emulator 127.0.0.1:9000 get /` |
| CI | `dart analyze` and `dart test` in this folder |
| Web gallery | - |

`rtdb_cli`, a command-line tool on [`package:args`](https://pub.dev/packages/args) and
`firebase_database_dart`:

| Command | What it does |
| --- | --- |
| `get <path>` | Prints the value as JSON. Query flags below. |
| `set <path> <json>` | Replaces the value. |
| `update <path> <json-object>` | Merges the keys of an object (keys may be paths, `a/b`). |
| `push <path> <json>` | Writes under a new child key and prints the key. |
| `remove <path>` | Deletes the data. |
| `watch <path>` | Prints the value now and after every change, one JSON line each, until Ctrl-C; stops cleanly. Query flags below. |
| `export <path> [file]` | Writes the JSON to a file, or to standard output. |
| `import <path> <file>` | Replaces the data at the path with the JSON of a file (`-` for stdin). |

Query flags of `get` and `watch`: `--order-by-child <path>`, `--order-by-key`, `--order-by-value`,
`--limit-to-first <n>`, `--limit-to-last <n>`, `--start-at`, `--end-at`, `--equal-to`. A bound is
read as JSON when it parses (`18`, `true`, `"7"`), as a plain string otherwise (`alice`).

Global options:

| Option | Variable | Meaning |
| --- | --- | --- |
| `--emulator host:port` | `FIREBASE_DATABASE_EMULATOR_HOST` | the Database emulator |
| `--project` | | project id; `demo-example` with an emulator |
| `--database-url` | | URL of a real database |
| `--api-key` | `FIREBASE_API_KEY` | Web API key for a real database |

Without an emulator and without an explicit `--database-url` the tool refuses to run, so it never
reaches a real project by accident.

Exit codes: `64` usage, `66` missing local file, `78` no backend configured, `1` any
`FirebaseDatabaseException` (printed as `code: message`).

```sh
dart run rtdb_cli --emulator 127.0.0.1:9000 set /users/ann '{"age": 31}'
dart run rtdb_cli --emulator 127.0.0.1:9000 get /users --order-by-child age --start-at 18
dart run rtdb_cli --emulator 127.0.0.1:9000 export /users users.json
```

The second command needs `".indexOn": "age"` at `/users` in the rules: the server refuses a filtered
`get` on an unindexed child with `index-not-defined`.
