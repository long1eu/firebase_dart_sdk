# Folding field transforms into set/patch mutations (upstream d40e7f1, df6a201, 8655b90, 7055d2a)

Scope: package `cloud_firestore/cloud_firestore_vm`. Protos already have `Write.update_transforms` (commit 36bcc4b).

## What changes

| File (under lib/src/firebase/firestore) | Change |
|---|---|
| `model/mutation/mutation.dart` | `Mutation` gets a `fieldTransforms` list (default empty) and owns `serverTransformResults`, `localTransformResults`, `transformObject`, `extractTransformBaseValue` (replaces abstract `extractBaseValue`). Doc comments updated. |
| `model/mutation/set_mutation.dart`, `patch_mutation.dart` | Optional `fieldTransforms` constructor arg; `applyToRemoteDocument` applies server transform results when present (no more "no transform results" assert); `applyToLocalView` applies local transform results; equality/hashCode/toString include transforms. |
| `model/mutation/delete_mutation.dart` | Drop `extractBaseValue`; keep assert that no transform results arrive. |
| `model/mutation/transform_mutation.dart` | Deleted. |
| `model/mutation/mutation_result.dart`, `transform_operation.dart`, `value/server_timestamp_value.dart` | Doc comments only. `MutationResult.transformResults` becomes non-null (empty list), as upstream 8655b90. |
| `core/user_data.dart` | `toMutationList` becomes `toMutation` returning one Set/Patch mutation carrying the transforms. Callers (`document_reference.dart`, `write_batch.dart`, `core/transaction.dart`) wrap/add a single mutation. |
| `local/local_store.dart` | `extractBaseValue` -> `extractTransformBaseValue`. |
| `remote/remote_serializer.dart` | `encodeMutation` puts transforms in `Write.updateTransforms` of set/patch writes; `decodeMutation` reads `updateTransforms`; the `transform` write branch is removed; `decodeMutationResult` returns an empty list for no transform results. |
| `local/local_serializer.dart` | `decodeMutationBatch` squashes legacy transform writes (see below). Encoding is the new form. |

The local cache proto (`mutation.proto`) does not change; it stores `google.firestore.v1.Write` messages.

## Semantics decision (one deliberate difference from upstream)

Upstream computes the local transform results from the document as it was before the set/patch. That makes
`set({a: increment(1)})` over `{a: 5}` show 6 locally (the backend applies transforms after the write, giving 1), and it
changes what an old persisted `[set, transform]` pair evaluates to. To keep the behaviour of the Dart port
unchanged (and legacy batches evaluating exactly as before), set/patch compute the new data first and evaluate the
transforms against that intermediate document (keeping the existing `baseDoc` fallback for the cleared nested map case).
Server transform results are likewise merged on top of the written data.

## Legacy decode strategy (LocalSerializer)

Old batches contain `[..., set|patch, transform, ...]` where the transform write has `exists: true`. On decode, iterate
forward; when write `i+1` has a `transform` and write `i` is an `update` without a transform, build a copy of write `i`
with the transform's field transforms appended to `updateTransforms` and decode that, skipping `i+1`. A `transform`
write that is not preceded by an update (upstream hard-asserts here) is decoded as a patch with an empty mask,
precondition `exists: true` and the transforms, which has exactly the old TransformMutation semantics (no effect on
missing docs), so a cache never fails to open. `baseWrites` never contain transform writes (they are set/patch built from
base values), but are decoded through the same path.
Remote `decodeMutation` no longer accepts a bare transform write (nothing sends one).

## Risks

- Wire: a transform folded into set/patch only works on backends supporting `update_transforms` (emulator does; production since 2020).
- Mutation batch size: batches with transforms were split into 2 writes; now 1 (fewer writes per commit; matches upstream).
- Equality of mutations now includes transforms; tests comparing lists of mutations must be updated.
- Other worktrees touch `remote_serializer.dart` (query encoding): edits here are confined to the mutation section.

## Test plan

- Unit: `model/mutation_test.dart` (transforms on set/patch, server ack with transform results), `remote_serializer_test.dart`
  (encode/decode set/patch with updateTransforms, mutation results), local store tests (memory + sqlite) using folded mutations,
  new `local_serializer_test` legacy-compat test building old-format `WriteBatch` bytes and expecting the folded mutation.
- Spec tests: re-run existing json spec tests (`test/res/json`); port any whose expectations changed (write counts).
- Integration against the emulator: array_transforms, array_transforms_server_application, server_timestamp, numeric_transformas,
  write_batch, transaction.
- `./tool/test_all.sh` green.
