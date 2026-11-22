# syncPointSpec.json

`syncPointSpec.json` is copied unchanged from the Firebase JS SDK:

- Repository: https://github.com/firebase/firebase-js-sdk
- File: `packages/database/test/helpers/syncPointSpec.json`
- Checkout: commit `a086865b469580a3c9e76eae810e467a3dc7334f` (file last changed in `025f2a1`)
- License: Apache License 2.0, Copyright Google LLC

The Android SDK has an older copy at `firebase-database/src/test/resources/syncPointSpec.json`
(firebase-android-sdk `2cfdd03`, file last changed in `00d4626`, 8,203 lines). The two copies are
not identical: the JS copy adds four scenarios for `startAfter`/`endBefore` and fixes spelling in
one scenario name (`User child overwrite for nonexistent server node`, Android: `non-existent`),
in some comments and in some data strings. The JS copy is used because the skeleton's
`QueryParams` follows JS for `startAfter`/`endBefore`.

The runner (`sync_point_spec_runner.dart`) follows JS `test/helpers/syncpoint-util.ts` and Android
`core/SyncPointTest.java`; `sync_point_spec_test.dart` defines one test per scenario. Run one
scenario by name:

    dart test test/spec/sync_point_spec_test.dart -N 'Deep update raises all events'

(`-N` matches a plain substring; `-n` takes a regular expression.)
