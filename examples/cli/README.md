# cli

`firestore_cli`, a command-line tool on [`package:args`](https://pub.dev/packages/args) and
`cloud_firestore_dart`:

| Command | What it does |
| --- | --- |
| `import <file> -c <collection>` | Writes the objects of a JSON array (`-` for stdin) as documents, with `WriteBatch`es of up to 500 writes (`--batch-size`). An object with an `id` field (`--id-field`) gets that document id; the others get a generated one. |
| `export -c <collection> [filters]` | Runs a query on the backend and prints the documents as a JSON array, or writes them to `-o <file>`. The output is what `import` reads. |
| `watch -c <collection> [filters]` | Prints the documents of a query, then one line per change (`added`, `modified`, `removed`, the id and the fields as JSON) until Ctrl-C (or `--exit-after <n>` changes). |

Filters for `export` and `watch`: `-w 'age>=18'`, `-w 'city==Paris'`, `-w 'tags array-contains red'`,
`-w 'role in ["admin","owner"]'` (repeatable; the value is read as JSON when it is valid JSON,
else as a string), `--order-by age:desc`, `--limit 10`. The id is not a field of the document,
so `-w 'id==...'` matches nothing.

Values that JSON has no type for are written in the tagged form of their `toJson()` (the same
form as the JS SDK's `toJSON()`), and `import` reads that form back:

```json
{"type": "firestore/timestamp/1.0", "seconds": 1700000000, "nanoseconds": 123456000}
{"type": "firestore/documentReference/1.0", "referencePath": "users/ada"}
```

Bytes, geo points and vectors work the same way. Timestamps come back truncated to the
microsecond: against the emulator, an imported `"nanoseconds": 5` was exported as `0`.

What it shows:

- Batched writes (`firestore.batch()`, `commit()`): each batch is atomic. The batches are
  committed one after the other, so after a failure the tool has written exactly the batches it
  printed as committed.
- `get(Source.server)` for `export`: an export never comes from a stale cache; without a
  connection it fails.
- A listener (`snapshots`) and `docChanges` for `watch`; Ctrl-C cancels it and terminates the
  instance so the process exits.
- Exit codes: `64` for usage errors, `65` for invalid JSON, `66` for a missing file, `78` when no
  backend is configured, `1` for a Firestore error.

## Run it against the Firestore emulator

Needs the Dart SDK (3.8 or later) and a Firestore emulator. From this directory:

```sh
firebase emulators:start --only firestore --project demo-example    # in another terminal

dart pub get
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
echo '[{"id": "ada", "age": 36}, {"id": "alan", "age": 41}]' > people.json
dart run bin/firestore_cli.dart import people.json -c people
dart run bin/firestore_cli.dart export -c people -w 'age>40'
dart run bin/firestore_cli.dart watch -c people --order-by age
```

For repeated use, compile it: `dart compile exe bin/firestore_cli.dart -o firestore_cli`.

The tests compile the tool and run it against the emulator (the emulator tests are skipped
without it):

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart test
```

## Point it at a real project

Nothing about the project is in the files; everything comes from the environment:

| Variable | Meaning |
| --- | --- |
| `FIREBASE_PROJECT_ID` | The project id. Required when `FIRESTORE_EMULATOR_HOST` is not set. |
| `FIRESTORE_DATABASE` | A named database (default `(default)`). |
| `FIREBASE_API_KEY` | Optional: the Web API key of the project, sent with each request. Unset, no key is sent. |
| `GOOGLE_APPLICATION_CREDENTIALS` | A service account key file, if you use one. |

```sh
unset FIRESTORE_EMULATOR_HOST
gcloud auth application-default login         # or GOOGLE_APPLICATION_CREDENTIALS=/path/key.json
FIREBASE_PROJECT_ID=<your project> dart run bin/firestore_cli.dart export -c people --limit 5
```

The requests carry Application Default Credentials, which **bypass Firestore security rules**
(access is decided by IAM, the `Cloud Datastore User` role). Each imported document is one write
and each exported or watched document is one read on your bill. A filter on one field with an
order on another needs a composite index on a real project (the emulator does not ask for
one).

This tool has been run against the emulator only, not against a real project.

## Notes

- `pubspec.yaml` takes the three packages from this repository (path dependencies and
  `dependency_overrides`), so the example runs against the code next to it. Outside the
  repository, replace both with the versions on pub.dev (`^0.1.0`).
- `lib/firestore_from_env.dart` is the same file in the three examples of `examples/`.
