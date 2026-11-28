# cloud_functions_dart examples

Small command-line programs. All but `main.dart` run against the Functions emulator of this repository, whose
fixture (`tool/functions_emulator/functions`) has the functions they call, or against your own project.

```sh
# from the root of the repository
npm ci --prefix tool/functions_emulator/functions     # once
./tool/start_functions_emulator.sh 9501
cd cloud_functions/cloud_functions_dart && dart pub get
dart run example/call.dart --emulator 127.0.0.1:9501
```

Against a deployed project, `--emulator` is replaced by `--api-key <key> --app-id <app id> --project-id <project id>`
(and `--region`), and the functions the example calls must exist there.

| File | Shows |
|---|---|
| `main.dart` | One call of `echo` with positional arguments (the pub.dev example). |
| `call.dart` | Values, reading the result as `num` and `Map<String, Object?>`, a `FirebaseFunctionsException` with its code, details and HTTP status, a value that is refused before sending, a timeout and a cancel with `abortTrigger`. |
| `stream.dart` | `stream()`: each `CallableMessage` and the final `CallableResult`. |
| `emulator.dart` | The emulator and a signed-in user: an `AuthTokenProvider` that hands out an unsigned JWT, which the emulator accepts, and the function `context` that reports the user it saw. |

`common.dart` parses `--api-key`, `--app-id`, `--project-id`, `--region` and `--emulator` with `package:args`
(`FIREBASE_FUNCTIONS_EMULATOR_HOST` is used when `--emulator` is absent) and builds the `FirebaseFunctions`.
