// The configuration of the real-project harness (real_project.dart),
// read from environment variables only, and the text helpers that keep
// emails out of its output.

import 'package:firebase_core/firebase_core.dart';

/// The steps of the harness, in the order they run.
enum HarnessStep {
  /// `signInWithProvider(GoogleAuthProvider())`.
  google,

  /// GitHub: `linkWithProvider`, `signInWithProvider` with the link, `unlink`;
  /// with [HarnessConfig.githubAccountExists], first the
  /// `account-exists-with-different-credential` recovery.
  github,

  /// `User.reauthenticateWithProvider(GoogleAuthProvider())`.
  reauthenticate,

  /// TOTP: enrol, sign out, sign in through the `MultiFactorResolver`,
  /// unenrol.
  totp,

  /// `revokeAccessToken`, which is for Apple tokens only: reported as a skip.
  revoke,

  /// `setPersistence` from NONE back to LOCAL, checking where the session is.
  persistence,
}

/// The variable that selects the steps: names separated by commas or spaces,
/// or `all`.
const String stepsVariable = 'AUTH_HARNESS_STEPS';

/// Set to `1` to run the `account-exists-with-different-credential` part of
/// the GitHub step (see [HarnessConfig.githubAccountExists]).
const String githubAccountExistsVariable = 'AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS';

/// An optional email address passed to Google as `login_hint`, so that the
/// account chooser is skipped. Never printed.
const String googleLoginHintVariable = 'AUTH_HARNESS_GOOGLE_LOGIN_HINT';

const List<String> _firebaseVariables = <String>[
  'FIREBASE_API_KEY',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_APP_ID',
];

const List<String> _googleVariables = <String>[
  'GOOGLE_DESKTOP_CLIENT_ID',
  'GOOGLE_DESKTOP_CLIENT_SECRET',
];

const List<String> _githubVariables = <String>[
  'GITHUB_CLIENT_ID',
  'GITHUB_CLIENT_SECRET',
];

/// A configuration the harness cannot run with; [message] says what to set.
class HarnessConfigException implements Exception {
  /// An error that says what to fix.
  HarnessConfigException(this.message);

  /// What is wrong, and what to set.
  final String message;

  @override
  String toString() => 'HarnessConfigException: $message';
}

/// What the harness runs, and against which project.
///
/// Every step signs in with Google first, so the Firebase and Google
/// variables are always required; the GitHub ones only with
/// [HarnessStep.github].
class HarnessConfig {
  HarnessConfig._({
    required this.steps,
    required this.options,
    required this.googleClientId,
    required this.googleClientSecret,
    required this.githubClientId,
    required this.githubClientSecret,
    required this.githubAccountExists,
    required this.googleLoginHint,
  });

  /// Reads the configuration from [environment] (`Platform.environment`).
  ///
  /// Throws a [HarnessConfigException] that lists every missing variable, an
  /// unknown step name, or a malformed `FIREBASE_APP_ID`.
  factory HarnessConfig.fromEnvironment(Map<String, String> environment) {
    final List<HarnessStep> steps = parseSteps(environment[stepsVariable]);
    final List<String> required = <String>[
      ..._firebaseVariables,
      ..._googleVariables,
      if (steps.contains(HarnessStep.github)) ..._githubVariables,
    ];
    final List<String> missing = <String>[
      for (final String name in required)
        if ((environment[name] ?? '').trim().isEmpty) name,
    ];
    if (missing.isNotEmpty) {
      throw HarnessConfigException(
        'Set ${missing.join(', ')} (see "Real-project harness" in the README).',
      );
    }
    String value(String name) => environment[name]!.trim();
    final String appId = value('FIREBASE_APP_ID');
    return HarnessConfig._(
      steps: steps,
      options: FirebaseOptions(
        apiKey: value('FIREBASE_API_KEY'),
        appId: appId,
        messagingSenderId: senderIdOf(appId),
        projectId: value('FIREBASE_PROJECT_ID'),
      ),
      googleClientId: value('GOOGLE_DESKTOP_CLIENT_ID'),
      googleClientSecret: value('GOOGLE_DESKTOP_CLIENT_SECRET'),
      githubClientId: environment['GITHUB_CLIENT_ID']?.trim(),
      githubClientSecret: environment['GITHUB_CLIENT_SECRET']?.trim(),
      githubAccountExists: parseFlag(
        githubAccountExistsVariable,
        environment[githubAccountExistsVariable],
      ),
      googleLoginHint: switch (environment[googleLoginHintVariable]?.trim()) {
        null || '' => null,
        final String hint => hint,
      },
    );
  }

  /// The steps to run, in the order of [HarnessStep].
  final List<HarnessStep> steps;

  /// The options of the Firebase app.
  final FirebaseOptions options;

  /// The client id of the Google "Desktop app" OAuth client.
  final String googleClientId;

  /// The client secret of the Google "Desktop app" OAuth client.
  final String googleClientSecret;

  /// The `login_hint` of the Google sign-ins, from
  /// [googleLoginHintVariable]; null when not set. An email address: never
  /// printed.
  final String? googleLoginHint;

  /// The client id of the GitHub OAuth App; null without [HarnessStep.github].
  final String? githubClientId;

  /// The client secret of the GitHub OAuth App.
  final String? githubClientSecret;

  /// Whether the GitHub step starts with a GitHub sign-in that must fail with
  /// `account-exists-with-different-credential` (the project allows one
  /// account per email address, and the GitHub account has the email of the
  /// Google account). Off by default: if either is not true, that sign-in
  /// creates a new account, which the harness cannot delete.
  final bool githubAccountExists;
}

/// The steps named in [value], in the order of [HarnessStep], without
/// duplicates. `all` selects every step.
///
/// Throws a [HarnessConfigException] for an empty value or an unknown name.
List<HarnessStep> parseSteps(String? value) {
  final List<String> names = <String>[
    for (final String name in (value ?? '').split(RegExp(r'[\s,]+')))
      if (name.isNotEmpty) name.toLowerCase(),
  ];
  if (names.isEmpty) {
    throw HarnessConfigException(
      'Set $stepsVariable to "all" or to some of: ${_stepNames()}.',
    );
  }
  if (names.contains('all')) {
    return HarnessStep.values;
  }
  final Set<HarnessStep> selected = <HarnessStep>{};
  for (final String name in names) {
    final HarnessStep? step = HarnessStep.values.asNameMap()[name];
    if (step == null) {
      throw HarnessConfigException(
        'Unknown step "$name" in $stepsVariable; the steps are all, '
        '${_stepNames()}.',
      );
    }
    selected.add(step);
  }
  return <HarnessStep>[
    for (final HarnessStep step in HarnessStep.values)
      if (selected.contains(step)) step,
  ];
}

/// Reads an on/off variable: unset, empty, `0` or `false` is off; `1` or
/// `true` is on. Throws a [HarnessConfigException] for anything else.
bool parseFlag(String name, String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case '' || '0' || 'false':
      return false;
    case '1' || 'true':
      return true;
    default:
      throw HarnessConfigException('Set $name to 1 or 0, not "$value".');
  }
}

/// The sender id inside a Firebase app id (`1:<sender id>:<platform>:<hash>`).
///
/// Throws a [HarnessConfigException] for an id of another shape.
String senderIdOf(String appId) {
  final RegExpMatch? match = RegExp(r'^\d+:(\d+):\w+:\w+$').firstMatch(appId);
  if (match == null) {
    throw HarnessConfigException(
      'FIREBASE_APP_ID should look like 1:<number>:<platform>:<hash> (the App '
      'ID of an app in the project settings).',
    );
  }
  return match.group(1)!;
}

String _stepNames() =>
    HarnessStep.values.map((HarnessStep step) => step.name).join(', ');

/// [email] with all of the local part but its first character hidden:
/// `a***@example.com`. Null or empty gives `(no email)`.
String maskEmail(String? email) {
  if (email == null || email.isEmpty) {
    return '(no email)';
  }
  final int at = email.lastIndexOf('@');
  if (at <= 0) {
    return '***';
  }
  return '${email[0]}***${email.substring(at)}';
}

final RegExp _email = RegExp(
  r'[^\s@<>"(),;:]+@[^\s@<>"(),;:]+\.[^\s@<>"(),;:]+',
);

/// [text] with every email address in it masked as [maskEmail] does, and cut
/// to [maxLength] characters.
String redact(String text, {int maxLength = 200}) {
  final String masked = text.replaceAllMapped(
    _email,
    (Match match) => maskEmail(match.group(0)),
  );
  return masked.length <= maxLength
      ? masked
      : '${masked.substring(0, maxLength)}...';
}
