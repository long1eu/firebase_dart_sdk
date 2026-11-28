# Data Connect production verification kit

`firebase_data_connect_dart` was built against the Data Connect emulator and the source of the official SDKs. The
emulator answers differently from production in places the client has to get right: the REST error body, which
headers the service requires, whether it accepts the API key as a header, the WebSocket path, and what an
`UNAUTHENTICATED` mutation did. This kit runs the client against a **real** Firebase project and prints `PASS`,
`FAIL`, `INCONCLUSIVE` or `SKIPPED` with a one-line explanation for each item. It answers the facts P1 to P15 of
the specification that the emulator cannot.

The code is `firebase_data_connect/firebase_data_connect_dart/tool/verify_production.dart`; `run.sh` here runs it
from the right directory. It is modelled on the other kits (`tool/verify_production_storage`,
`tool/verify_production_remote_config`).

**Do not run it without the owner's approval.** It contacts a real Firebase project. Stage A sends requests to a
service that does not exist; stage B needs a deployed service with Cloud SQL, which costs money while it runs and
is deployed only when the owner agrees to the commands and the instance tier.

## The two stages

**Stage A: no Cloud SQL.** Requests to a service and connector that do not exist in the project. It needs only a
project, an app id and an API key.

- one REST and one gRPC call to a non-existent connector, printing the raw error body with every token redacted
  (the production form of the error, P3);
- the same with and without `?key=` (P4: does the service accept a REST call with no key, a gRPC call with no key,
  and does it accept `X-Goog-Api-Key` instead);
- with `x-client-version: dart/<version>` (P8);
- without each routing header, `x-goog-request-params` and `x-firebase-sqlconnect-affinity`, over a raw gRPC call
  (P6);
- a WebSocket upgrade on both path forms, the dot form JS builds and the slash form that works on the emulator
  (P1).

**Stage B: a deployed service.** It deploys nothing itself: you deploy the fixture connector of
`tool/data_connect_emulator/dataconnect/` plus the mutation
`mutation DeleteItem($id: UUID!) @auth(level: PUBLIC) { item_delete(id: $id) }`, which the kit uses to delete what it
created, and pass its names with `--location`, `--service` and `--connector`.

- a query and a mutation on the VM (gRPC) and from Chrome (REST);
- a GraphQL error and an unknown operation on both, expecting the same codes;
- an unauthenticated call to an `@auth(level: USER)` query (the status and whether a retry happened);
- the form of numbers in results (P5), the entity metadata with and without `clientCache` (P12), and a subscription
  push after a mutation (P2).

## Before you run it

1. Use a project you can spare. Register a web app in it (project settings, "Your apps"): that gives the **app id**
   (`1:<project number>:web:<hash>`) and the **API key**. Use a key without restrictions, or one whose API
   restrictions allow the Firebase Data Connect API.
2. Stage B: deploy the service first (`firebase deploy --only dataconnect`, with the fixture's `dataconnect.yaml`
   edited to your location, service id and Cloud SQL instance). The first deploy creates a Cloud SQL instance, which
   is billed until you delete it.

## What it does to your project

- Stage A changes nothing: every request targets a connector that does not exist.
- Stage B inserts rows with `CreateItem` and deletes each of them with `DeleteItem`, also when a check failed and
  after Ctrl-C. A row it could not delete is named in the report.
- Stage B creates a throwaway user in Firebase Auth through `firebase_auth_providers_dart`
  (`FirebaseUserAuth`), as the Storage and Database kits do, and deletes it at the end.
- It never prints the API key, an ID token or an App Check token. Raw error bodies are printed with tokens
  redacted; for failures it prints the status and the sanitised server message only. It prints the project id and
  the app id first.
- Against the real project it does nothing without `--yes`: without it, it prints the plan and exits 2.

## Commands

From the repository root (the folder that holds `tool/` and `firebase_data_connect/`):

    export FIREBASE_TEST_PROJECT_ID=my-project
    export FIREBASE_TEST_APP_ID=1:123456789:web:abc123
    export FIREBASE_API_KEY=...                                  # or --api-key=

    tool/verify_production_data_connect/run.sh --stage a         # prints the plan, does nothing
    tool/verify_production_data_connect/run.sh --yes --stage a
    tool/verify_production_data_connect/run.sh --yes --stage b \
      --location=us-central1 --service=my-service --connector=my-connector

Options: `--project-id`, `--app-id`, `--api-key` (instead of the variables), `--location`, `--service`,
`--connector` (stage B, and the names that stage A sends requests to), `--stage a|b`, `--yes`, `--help`.

Save the report: `... --yes --stage a | tee verify_data_connect_report_a.txt`. It holds the project id and the app
id, and no credentials.

Exit code: 0 when no item failed, 1 when one is `FAIL`, 2 for a missing option or a missing `--yes`, 64 for an
unknown option.

## How to read the result

| Result | Meaning |
|---|---|
| `PASS` | the service behaved as the client assumes |
| `FAIL` | it did not; the line gives the status and the sanitised server message. Send the whole report to the maintainer |
| `INCONCLUSIVE` | the item could not tell (for example the service pushed nothing in the window): says nothing against the client |
| `SKIPPED` | an earlier item it needs did not pass, or the stage was not selected |

A `FAIL` of P4 (the key is not accepted as sent) or P1 (neither WebSocket path works) does not break 0.1.0, which
ships neither realtime nor a key-less call; they decide what the next release does.

## Not verified

- Realtime beyond the first push: reconnects, long-running streams.
- A connector with App Check enforced (P15): it needs a project with enforcement and a provider.
- Anything that needs the owner's other projects or an Android or iOS app: the kit runs as a desktop program.
