# Auth upstream review: brief

Goal: keep the Auth client (`firebase_auth/firebase_auth_providers_dart`, class `FirebaseUserAuth`) in step with upstream.
The client was written in November 2026 against the JS SDK `@firebase/auth` 1.13.10. The reference for behaviour is the iOS SDK.
The JS SDK is the cross-check. Where they differ, follow iOS and note the difference.

This is the Auth counterpart of the Firestore review in the parent folder. It is smaller: one pass per month, by hand or by one agent.

## What to read

- JS: `firebase/firebase-js-sdk`, path `packages/auth`.
- iOS: `firebase/firebase-ios-sdk`, path `FirebaseAuth`.

List the commits since the last pass with the public GitHub API (no login to Firebase or Google is needed):

```
gh api "repos/firebase/firebase-js-sdk/commits?path=packages/auth&since=<date>T00:00:00Z&per_page=100" \
  --jq '.[] | [.sha[0:8], .commit.committer.date[0:10], (.commit.message|split("\n")[0])] | @tsv'
gh api "repos/firebase/firebase-ios-sdk/commits?path=FirebaseAuth&since=<date>T00:00:00Z&per_page=100" --jq '<same>'
```

For each commit that is not obviously tests, CI or release notes, read the file list and the source diff
(`gh api repos/<repo>/commits/<sha>`, or the same URL with `-H "Accept: application/vnd.github.diff"`).
Then look in the Dart client with grep: does the code the commit touches exist, and is the bug or feature already handled?

## How to classify

One class per commit:

- **applies**: the client has the same gap. A user could see the bug, or the behaviour differs from upstream. Say which Dart file would change.
- **already done**: the client has the fix or the behaviour already. Say where, in a few words.
- **browser or device only**: it concerns IndexedDB, Trusted Types, the keychain, APNs, reCAPTCHA in a view, dispatch queues or other things the Dart client does not have. Say what, so a later reader can tell why.
- **no effect**: tests, CI, changelog, version bumps, docs.
- **not read**: you did not look at the diff. Say so; do not guess.

Rules:

- Judge by the diff, not by the subject line. Subjects are often too short.
- A fix for a crash on malformed server data usually applies: the Dart client reads the same JSON.
- Threading fixes in Swift usually do not apply. Dart has one isolate and the client already runs one refresh at a time.
- Anything touching multi-factor applies to the multi-factor work in progress. Mark it so and keep it for that work.
- If a commit changes the wire format (request or response fields, error codes), note it even when it is small.

## Where to record

One file per pass: `auth/review_<YYYY-MM>.md`. Start the next pass from the last date in the newest file.
Each file has the date range, the two sections (JS, iOS), one line per commit
(`sha8 | date | subject | class | one short reason`), and at the end a list of the commits that apply.
When an "applies" item is fixed, add its Dart commit to the line in the old file; do not delete the line.
Plain English, short sentences, no names of people.
