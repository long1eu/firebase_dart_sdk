// The real-project harness: drives the official firebase_auth API, on top of
// this package, against a real Firebase project, with a person at the
// browser. Skipped unless AUTH_HARNESS_STEPS is set; see "Real-project
// harness" in the README for the command and the console setup.
//
// It runs under `flutter test` because package:flutter needs the engine's
// dart:ui, which `dart run` does not have. It uses a plain test() with no
// test binding, so HttpClient is real. `flutter test` does not forward stdin,
// so codes are typed into a page on 127.0.0.1 (code_prompt.dart).

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show FileAuthStorage, openInSystemBrowser;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cleanup.dart';
import 'code_prompt.dart';
import 'harness_config.dart';
import 'harness_steps.dart';

void main() {
  final String? steps = Platform.environment[stepsVariable];
  test(
    'real-project auth harness',
    () async {
      final (List<StepResult> results, List<String> problems) = await _run(
        HarnessConfig.fromEnvironment(Platform.environment),
      );
      expect(
        results.where((StepResult r) => r.status == StepStatus.fail),
        isEmpty,
        reason: 'a step failed',
      );
      expect(problems, isEmpty, reason: 'a cleanup step failed');
    },
    skip: steps == null || steps.trim().isEmpty
        ? 'Set $stepsVariable to run the real-project harness (README).'
        : false,
    timeout: Timeout.none,
  );
}

Future<(List<StepResult>, List<String>)> _run(HarnessConfig config) async {
  final Directory sessionDir = await Directory.systemTemp.createTemp(
    'auth_harness_',
  );
  final RecordingStorage storage = RecordingStorage(
    FileAuthStorage('${sessionDir.path}/sessions.json'),
  );
  FirebaseAuthDart.use(
    storageFor: (FirebaseApp app) => storage,
    useDartCore: true,
    oauthProviders: <OAuthLoopbackProvider>[
      OAuthLoopbackProvider.google(
        clientId: config.googleClientId,
        clientSecret: config.googleClientSecret,
        loginHint: config.googleLoginHint,
      ),
      if (config.githubClientId != null)
        OAuthLoopbackProvider.github(
          clientId: config.githubClientId!,
          clientSecret: config.githubClientSecret!,
        ),
    ],
  );
  await Firebase.initializeApp(options: config.options);
  final FirebaseAuth auth = FirebaseAuth.instance;
  await auth.authStateChanges().first;
  final LoopbackCodePrompt prompt = LoopbackCodePrompt(
    log: print,
    open: openInSystemBrowser,
  );
  final CleanupLedger ledger = CleanupLedger();
  final HarnessRun run = HarnessRun(
    auth: auth,
    codes: prompt,
    ledger: ledger,
    storage: storage,
    log: print,
    githubAccountExists: config.githubAccountExists,
  );
  print('Session file in ${sessionDir.path} (deleted at the end).');
  final List<StepResult> results = <StepResult>[];
  List<String> problems = <String>[];
  try {
    for (final HarnessStep step in config.steps) {
      print('-- ${step.name}');
      final StepResult result = await run.runStep(step);
      results.add(result);
      print(result.line());
    }
  } finally {
    problems = await _finish(auth, ledger, prompt, sessionDir);
  }
  return (results, problems);
}

/// Runs the pending undo actions, reports what is left, signs out, and
/// deletes the session file; returns what is left on the account.
Future<List<String>> _finish(
  FirebaseAuth auth,
  CleanupLedger ledger,
  LoopbackCodePrompt prompt,
  Directory sessionDir,
) async {
  await ledger.runPending(describeError);
  final List<String> problems = ledger.problems;
  if (problems.isEmpty) {
    print('CLEANUP OK: the account is as the harness found it.');
  } else {
    print('CLEANUP FAILED: fix these by hand:');
    for (final String problem in problems) {
      print('  - $problem');
    }
  }
  try {
    await auth.signOut();
  } on FirebaseAuthException catch (e) {
    print('Sign-out failed: ${describeError(e)}');
  }
  await prompt.close();
  await sessionDir.delete(recursive: true);
  return problems;
}
