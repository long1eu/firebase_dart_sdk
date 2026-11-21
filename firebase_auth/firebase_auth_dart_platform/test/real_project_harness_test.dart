// Offline tests of the real-project harness (test/real_project/): its
// configuration, its output helpers, the code page, the cleanup bookkeeping,
// and the steps themselves against the fake backend, with a simulated
// browser. Nothing here contacts a real project.

import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_dart_platform/firebase_auth_dart_platform.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart'
    show FileAuthStorage, InMemoryAuthStorage;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_backend.dart';
import 'real_project/cleanup.dart';
import 'real_project/code_prompt.dart';
import 'real_project/harness_config.dart';
import 'real_project/harness_steps.dart';

const Map<String, String> _baseEnvironment = <String, String>{
  'AUTH_HARNESS_STEPS': 'google',
  'FIREBASE_API_KEY': 'key-value',
  'FIREBASE_PROJECT_ID': 'demo-harness',
  'FIREBASE_APP_ID': '1:1234:web:abcd',
  'GOOGLE_DESKTOP_CLIENT_ID': 'google-id',
  'GOOGLE_DESKTOP_CLIENT_SECRET': 'google-secret-value',
};

Matcher _configError(String text) => throwsA(
  isA<HarnessConfigException>().having(
    (HarnessConfigException e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  group('configuration', _configurationTests);
  group('output', _outputTests);
  group('cleanup ledger', _ledgerTests);
  group('code page', _codePageTests);
  group('steps on the fake backend', () {
    _setUpFakeProject();
    group('google, totp, revoke, persistence', _stepTests);
    group('github', _githubTests);
  });
}

void _configurationTests() {
  test('steps run in their fixed order, without duplicates', () {
    expect(parseSteps(' totp, google  google\tpersistence '), <HarnessStep>[
      HarnessStep.google,
      HarnessStep.totp,
      HarnessStep.persistence,
    ]);
    expect(parseSteps('ALL'), HarnessStep.values);
    expect(parseSteps('google,all'), HarnessStep.values);
  });

  test('no step or an unknown step is an error that names the steps', () {
    expect(() => parseSteps(null), _configError('reauthenticate'));
    expect(() => parseSteps(' , '), _configError('AUTH_HARNESS_STEPS'));
    expect(() => parseSteps('google,delete'), _configError('"delete"'));
  });

  test('every missing variable is listed, the GitHub ones only with the '
      'github step', () {
    expect(
      () => HarnessConfig.fromEnvironment(<String, String>{
        'AUTH_HARNESS_STEPS': 'google',
        'FIREBASE_API_KEY': ' ',
      }),
      _configError(
        'Set FIREBASE_API_KEY, FIREBASE_PROJECT_ID, FIREBASE_APP_ID, '
        'GOOGLE_DESKTOP_CLIENT_ID, GOOGLE_DESKTOP_CLIENT_SECRET (',
      ),
    );
    expect(
      () => HarnessConfig.fromEnvironment(<String, String>{
        ..._baseEnvironment,
        'AUTH_HARNESS_STEPS': 'github',
      }),
      _configError('Set GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET ('),
    );
  });

  test('a complete environment gives the options and the clients', () {
    final HarnessConfig config = HarnessConfig.fromEnvironment(<String, String>{
      ..._baseEnvironment,
      'AUTH_HARNESS_STEPS': 'github revoke',
      'GITHUB_CLIENT_ID': 'gh-id',
      'GITHUB_CLIENT_SECRET': 'gh-secret',
      'AUTH_HARNESS_GITHUB_ACCOUNT_EXISTS': '1',
    });
    expect(config.steps, <HarnessStep>[HarnessStep.github, HarnessStep.revoke]);
    expect(config.options.apiKey, 'key-value');
    expect(config.options.projectId, 'demo-harness');
    expect(config.options.messagingSenderId, '1234');
    expect(config.googleClientSecret, 'google-secret-value');
    expect(config.githubClientId, 'gh-id');
    expect(config.githubAccountExists, isTrue);
    expect(config.googleLoginHint, isNull);
  });

  test('the Google login hint is optional', () {
    expect(
      HarnessConfig.fromEnvironment(<String, String>{
        ..._baseEnvironment,
        'AUTH_HARNESS_GOOGLE_LOGIN_HINT': ' ada@example.com ',
      }).googleLoginHint,
      'ada@example.com',
    );
    expect(
      HarnessConfig.fromEnvironment(<String, String>{
        ..._baseEnvironment,
        'AUTH_HARNESS_GOOGLE_LOGIN_HINT': '  ',
      }).googleLoginHint,
      isNull,
    );
  });

  test('a malformed app id or flag is an error that does not echo secrets', () {
    expect(
      () => HarnessConfig.fromEnvironment(<String, String>{
        ..._baseEnvironment,
        'FIREBASE_APP_ID': 'not-an-app-id',
      }),
      throwsA(
        isA<HarnessConfigException>().having(
          (HarnessConfigException e) => e.message,
          'message',
          allOf(
            contains('FIREBASE_APP_ID'),
            isNot(contains('google-secret-value')),
            isNot(contains('key-value')),
          ),
        ),
      ),
    );
    expect(parseFlag('X', null), isFalse);
    expect(parseFlag('X', 'false'), isFalse);
    expect(parseFlag('X', ' TRUE '), isTrue);
    expect(() => parseFlag('X', 'yes'), _configError('Set X to 1 or 0'));
  });
}

void _outputTests() {
  test('emails are masked to their first character and domain', () {
    expect(maskEmail('ada@example.com'), 'a***@example.com');
    expect(maskEmail('a@b.co'), 'a***@b.co');
    expect(maskEmail(null), '(no email)');
    expect(maskEmail(''), '(no email)');
    expect(maskEmail('@example.com'), '***');
    expect(maskEmail('no-at-sign'), '***');
  });

  test('redact masks the emails in a text and cuts it', () {
    expect(
      redact('user ada.l@example.com and bob@x.org failed'),
      'user a***@example.com and b***@x.org failed',
    );
    expect(redact('x' * 10, maxLength: 4), 'xxxx...');
  });

  test('describeError gives codes, with the server code when known', () {
    expect(
      describeError(
        DartFirebaseAuthException(
          code: 'invalid-credential',
          serverCode: 'INVALID_IDP_RESPONSE : bad token for ada@example.com',
          httpStatus: 400,
        ),
      ),
      'invalid-credential (server: INVALID_IDP_RESPONSE)',
    );
    expect(
      describeError(FirebaseAuthException(code: 'user-cancelled')),
      'user-cancelled',
    );
    expect(describeError(StepFailure('wrong-account')), 'wrong-account');
    expect(
      describeError(StateError('ada@example.com')),
      'StateError: Bad state: a***@example.com',
    );
  });

  test('a result is one line', () {
    expect(
      const StepResult(HarnessStep.google, StepStatus.pass).line(),
      'PASS google',
    );
    expect(
      const StepResult(HarnessStep.totp, StepStatus.fail, 'timeout').line(),
      'FAIL totp: timeout',
    );
  });
}

void _ledgerTests() {
  test('an undo that ran is no longer pending', () async {
    final CleanupLedger ledger = CleanupLedger();
    int runs = 0;
    final CleanupToken token = ledger.register('unlink', () async => runs++);
    expect(ledger.pending, <String>['unlink']);
    await ledger.run(token);
    await ledger.run(token);
    await ledger.runPending(describeError);
    expect(runs, 1);
    expect(ledger.pending, isEmpty);
    expect(ledger.problems, isEmpty);
  });

  test('a failed undo stays pending and runs once more at the end, newest '
      'first; what fails again is a problem', () async {
    final CleanupLedger ledger = CleanupLedger();
    final List<String> order = <String>[];
    bool failUnlink = true;
    final CleanupToken unlink = ledger.register('unlink', () async {
      order.add('unlink');
      if (failUnlink) {
        throw FirebaseAuthException(code: 'network-request-failed');
      }
    });
    ledger.register('unenrol', () async {
      order.add('unenrol');
      throw FirebaseAuthException(code: 'requires-recent-login');
    });
    await expectLater(
      ledger.run(unlink),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(ledger.pending, <String>['unlink', 'unenrol']);
    failUnlink = false;
    ledger.recordManual('delete account x by hand');
    await ledger.runPending(describeError);
    expect(order, <String>['unlink', 'unenrol', 'unlink']);
    expect(ledger.pending, isEmpty);
    expect(ledger.problems, <String>[
      'unenrol: requires-recent-login',
      'delete account x by hand',
    ]);
  });
}

void _codePageTests() {
  late LoopbackCodePrompt prompt;
  late List<String> logged;
  late List<Uri> opened;
  final http.Client browser = http.Client();

  setUp(() {
    logged = <String>[];
    opened = <Uri>[];
    prompt = LoopbackCodePrompt(
      log: logged.add,
      open: (Uri url) async => opened.add(url),
    );
  });
  tearDown(() => prompt.close());
  tearDownAll(browser.close);

  test('the code posted to the page answers ask', () async {
    final Future<String> answer = prompt.ask(
      'The code',
      otpauthUri: 'otpauth://totp/x?secret=ABC&issuer=a<b',
    );
    await pumpEventQueue();
    final Uri url = opened.single;
    expect(url.host, '127.0.0.1');
    expect(logged.single, contains(url.toString()));
    final http.Response page = await browser.get(url);
    expect(page.body, contains('secret=ABC&amp;issuer=a&lt;b'));
    final http.Response wrong = await browser.post(url, body: {'code': '12a'});
    expect(wrong.statusCode, HttpStatus.badRequest);
    final http.Response ok = await browser.post(
      url,
      body: {'code': ' 123 456 '},
    );
    expect(ok.statusCode, HttpStatus.ok);
    expect(await answer, '123456');
    final http.Response late = await browser.post(url, body: {'code': '1'});
    expect(late.statusCode, HttpStatus.conflict);
  });

  test('another path is not found, and ask times out', () async {
    final LoopbackCodePrompt quick = LoopbackCodePrompt(
      log: (_) {},
      timeout: const Duration(milliseconds: 50),
    );
    final Future<String> answer = quick.ask('code');
    await expectLater(answer, throwsA(isA<Exception>()));
    final Uri url = quick.url!;
    final http.Response other = await browser.post(
      url.replace(path: '/'),
      body: {'code': '123456'},
    );
    expect(other.statusCode, HttpStatus.notFound);
    await quick.close();
  });

  test('normalizeCode keeps 6 to 8 digits only', () {
    expect(normalizeCode('123-456'), '123456');
    expect(normalizeCode('12345678'), '12345678');
    expect(normalizeCode('12345'), '');
    expect(normalizeCode('123456789'), '');
    expect(normalizeCode(null), '');
  });
}

/// Answers the codes the steps ask for, from [codes], and records the prompts.
class _Codes implements CodeSource {
  _Codes(this.codes);

  final List<String> codes;
  final List<String> prompts = <String>[];
  final List<String?> uris = <String?>[];

  @override
  Future<String> ask(String prompt, {String? otpauthUri}) async {
    prompts.add(prompt);
    uris.add(otpauthUri);
    return codes.removeAt(0);
  }
}

/// The browser of the provider flows: redirects to the loopback server at
/// once, with a code and the state it was sent.
final List<Uri> _presented = <Uri>[];

Future<void> _followRedirect(Uri url) async {
  _presented.add(url);
  final Map<String, String> query = url.queryParameters;
  final Uri redirect = Uri.parse(query['redirect_uri']!).replace(
    queryParameters: <String, String>{
      'code': 'the-code',
      'state': query['state']!,
    },
  );
  final http.Client client = http.Client();
  try {
    await client.get(redirect);
  } finally {
    client.close();
  }
}

/// The account of the fake project: `google-user`, signed in with Google,
/// with GitHub linked or not, and its second factors in the fake backend.
class _Project {
  _Project(this.backend);

  final FakeBackend backend;
  bool githubLinked = false;

  /// Whether a GitHub sign-in of the unlinked account answers
  /// `needConfirmation` (one account per email) instead of a new account.
  bool oneAccountPerEmail = true;

  /// How many more `mfaEnrollment:start` requests answer
  /// `requires-recent-login`.
  int recentLoginsRequired = 0;

  static const String uid = 'google-user';

  List<Map<String, Object?>> get _factors =>
      backend.factors[uid] ?? <Map<String, Object?>>[];

  http.Response? answer(http.Request request) {
    final String path = request.url.path;
    if (request.url.host == 'oauth2.googleapis.com') {
      return jsonResponse(<String, Object?>{
        'access_token': 'google-access-token',
        'id_token': unsignedJwt(<String, Object?>{
          'sub': 'google-sub',
          'nonce': _presented.last.queryParameters['nonce'],
        }),
        'expires_in': 3599,
        'token_type': 'Bearer',
      });
    }
    if (request.url.host == 'github.com') {
      return jsonResponse(<String, Object?>{
        'access_token': 'github-access-token',
        'token_type': 'bearer',
        'scope': 'read:user',
      });
    }
    if (path.endsWith('accounts:signInWithIdp')) {
      return _signInWithIdp(jsonDecode(request.body) as Map<String, Object?>);
    }
    if (path.endsWith('accounts:lookup')) {
      return _lookup();
    }
    if (path.endsWith('accounts:update')) {
      final Object? deleted =
          (jsonDecode(request.body) as Map<String, Object?>)['deleteProvider'];
      if (deleted is List && deleted.contains('github.com')) {
        githubLinked = false;
      }
    }
    if (path.endsWith('mfaEnrollment:start') && recentLoginsRequired > 0) {
      recentLoginsRequired--;
      return errorResponse('CREDENTIAL_TOO_OLD_LOGIN_AGAIN');
    }
    if (path.endsWith('accounts:revokeToken')) {
      return errorResponse('INVALID_IDP_RESPONSE');
    }
    return null;
  }

  http.Response _signInWithIdp(Map<String, Object?> body) {
    final String provider = Uri.splitQueryString(
      body['postBody']! as String,
    )['providerId']!;
    final bool linking = body['idToken'] != null;
    if (provider == 'github.com' && linking) {
      githubLinked = true;
    } else if (provider == 'github.com' && !githubLinked) {
      return oneAccountPerEmail
          ? jsonResponse(<String, Object?>{
              'needConfirmation': true,
              'email': 'ada@example.com',
              'providerId': 'github.com',
              'oauthAccessToken': 'github-access-token',
            })
          : _tokens(provider, isNewUser: true, localId: 'new-github-user');
    } else if (!linking && _factors.isNotEmpty) {
      return jsonResponse(<String, Object?>{
        'localId': uid,
        'email': 'ada@example.com',
        'mfaPendingCredential': 'pending:$uid',
        'mfaInfo': _factors,
      });
    }
    return _tokens(provider);
  }

  http.Response _tokens(
    String provider, {
    bool isNewUser = false,
    String localId = uid,
  }) => jsonResponse(<String, Object?>{
    'localId': localId,
    'providerId': provider,
    'isNewUser': isNewUser,
    'idToken': idToken(localId, provider: provider, email: 'ada@example.com'),
    'refreshToken': 'refresh:$localId',
    'expiresIn': '3600',
  });

  http.Response _lookup() => jsonResponse(<String, Object?>{
    'users': <Object?>[
      <String, Object?>{
        'localId': uid,
        'email': 'ada@example.com',
        'emailVerified': true,
        'createdAt': '1700000000000',
        'lastLoginAt': '1700000001000',
        if (_factors.isNotEmpty) 'mfaInfo': _factors,
        'providerUserInfo': <Object?>[
          <String, Object?>{'providerId': 'google.com', 'rawId': 'google-sub'},
          if (githubLinked)
            <String, Object?>{'providerId': 'github.com', 'rawId': '42'},
        ],
      },
    ],
  });
}

int _apps = 0;

final FakeBackend _backend = FakeBackend();
final Map<String, RecordingStorage> _storages = <String, RecordingStorage>{};
late Directory _sessions;
late _Project _project;

/// Installs this package on the fake backend once, with the simulated browser,
/// and a fresh [_Project] for each test.
void _setUpFakeProject() {
  setUpAll(() async {
    _sessions = await Directory.systemTemp.createTemp('harness_test_');
    FirebaseAuthDart.use(
      httpClient: _backend.client,
      useDartCore: true,
      storageFor: (FirebaseApp app) => _storages.putIfAbsent(
        app.name,
        () =>
            RecordingStorage(FileAuthStorage('${_sessions.path}/${app.name}')),
      ),
      oauthProviders: <OAuthLoopbackProvider>[
        OAuthLoopbackProvider.google(clientId: 'id', clientSecret: 'secret'),
        OAuthLoopbackProvider.github(clientId: 'id', clientSecret: 'secret'),
      ],
      presenter: CallbackPresenter(_followRedirect),
    );
  });
  tearDownAll(() => _sessions.delete(recursive: true));

  setUp(() {
    _backend.requests.clear();
    _backend.factors.clear();
    _project = _Project(_backend);
    _backend.override = _project.answer;
    _presented.clear();
  });
}

/// A run on the FirebaseAuth of a new app, so that each test starts signed
/// out, answering [codes] in order.
Future<(HarnessRun, CleanupLedger, _Codes)> _newRun(
  List<String> codes, {
  bool githubAccountExists = false,
}) async {
  final FirebaseApp app = await Firebase.initializeApp(
    name: 'harness${_apps++}',
    options: const FirebaseOptions(
      apiKey: 'test-api-key',
      appId: '1:1:web:1',
      messagingSenderId: '1',
      projectId: 'demo-unit',
    ),
  );
  final FirebaseAuth auth = FirebaseAuth.instanceFor(app: app);
  await auth.authStateChanges().first;
  final CleanupLedger ledger = CleanupLedger();
  final _Codes source = _Codes(codes);
  final HarnessRun run = HarnessRun(
    auth: auth,
    codes: source,
    ledger: ledger,
    storage: _storages[app.name]!,
    log: (_) {},
    githubAccountExists: githubAccountExists,
  );
  return (run, ledger, source);
}

void _stepTests() {
  test('google, reauthenticate, revoke and persistence', () async {
    final (HarnessRun run, CleanupLedger ledger, _) = await _newRun(<String>[]);
    Future<String> line(HarnessStep step) async =>
        (await run.runStep(step)).line();
    expect(await line(HarnessStep.google), 'PASS google');
    expect(run.primaryUid, _Project.uid);
    expect(await line(HarnessStep.reauthenticate), 'PASS reauthenticate');
    expect(
      await line(HarnessStep.revoke),
      allOf(
        startsWith('SKIP revoke: Apple-only'),
        contains('refused the placeholder token: invalid-credential'),
      ),
    );
    expect(
      _backend.bodyOf('accounts:revokeToken'),
      containsPair('token', placeholderAppleToken),
    );
    expect(await line(HarnessStep.persistence), 'PASS persistence');
    expect(await run.storage.holdsSession(), isTrue);
    expect(ledger.pending, isEmpty);
  });

  test('totp enrols, signs in through the resolver and unenrols', () async {
    final (HarnessRun run, CleanupLedger ledger, _Codes codes) = await _newRun(
      <String>[_backend.totpCode, _backend.totpCode],
    );
    expect((await run.runStep(HarnessStep.totp)).line(), 'PASS totp');
    expect(codes.prompts, hasLength(2));
    expect(codes.prompts.last, contains('NEXT code'));
    final Uri uri = Uri.parse(codes.uris.first!);
    expect(uri.scheme, 'otpauth');
    expect(uri.queryParameters['issuer'], totpDisplayName);
    expect(uri.path, contains('a***@example.com'));
    expect(uri.toString(), isNot(contains('ada@example.com')));
    expect(_backend.factors[_Project.uid], isEmpty);
    expect(ledger.pending, isEmpty);
    expect(run.auth.currentUser!.uid, _Project.uid);
  });

  test('totp signs in again with Google when the enrolment needs a recent '
      'sign-in, then enrols', () async {
    final (HarnessRun run, CleanupLedger ledger, _Codes codes) = await _newRun(
      <String>[_backend.totpCode, _backend.totpCode],
    );
    _project.recentLoginsRequired = 1;
    final int idpBefore = _backend.paths
        .where((String p) => p.endsWith('accounts:signInWithIdp'))
        .length;
    expect((await run.runStep(HarnessStep.totp)).line(), 'PASS totp');
    expect(_project.recentLoginsRequired, 0);
    expect(
      _backend.paths
          .where((String p) => p.endsWith('accounts:signInWithIdp'))
          .length,
      greaterThan(idpBefore + 1),
      reason: 'a reauthentication besides the second-factor sign-in',
    );
    expect(_backend.factors[_Project.uid], isEmpty);
    expect(ledger.pending, isEmpty);
    expect(codes.prompts, hasLength(2));
  });

  test('a wrong code at the totp sign-in fails the step, and the pending '
      'unenrol signs in again and removes the factor', () async {
    final (HarnessRun run, CleanupLedger ledger, _Codes codes) = await _newRun(
      <String>[_backend.totpCode, '000000', _backend.totpCode],
    );
    final StepResult result = await run.runStep(HarnessStep.totp);
    expect(result.status, StepStatus.fail);
    expect(_backend.factors[_Project.uid], hasLength(1));
    expect(ledger.pending, <String>['unenrol the TOTP factor "auth-harness"']);
    await ledger.runPending(describeError);
    expect(ledger.problems, isEmpty);
    expect(_backend.factors[_Project.uid], isEmpty);
    expect(codes.codes, isEmpty);
  });

  test('the session storage records which keys hold a value', () async {
    final RecordingStorage storage = RecordingStorage(InMemoryAuthStorage());
    expect(await storage.holdsSession(), isFalse);
    await storage.write('k', 'v');
    expect(await storage.holdsSession(), isTrue);
    await storage.write('k', null);
    expect(await storage.holdsSession(), isFalse);
  });
}

void _githubTests() {
  test('github links, signs in with the link and unlinks', () async {
    final (HarnessRun run, CleanupLedger ledger, _) = await _newRun(<String>[]);
    final StepResult result = await run.runStep(HarnessStep.github);
    expect(result.status, StepStatus.pass, reason: result.line());
    expect(_project.githubLinked, isFalse);
    expect(
      _backend.paths.where((String p) => p.endsWith('accounts:update')),
      isNotEmpty,
    );
    expect(ledger.pending, isEmpty);
  });

  test('github with the account-exists part recovers through the credential '
      'of the error', () async {
    final (HarnessRun run, CleanupLedger ledger, _) = await _newRun(
      <String>[],
      githubAccountExists: true,
    );
    final StepResult result = await run.runStep(HarnessStep.github);
    expect(result.status, StepStatus.pass, reason: result.line());
    expect(result.detail, startsWith('account-exists recovery'));
    expect(_project.githubLinked, isFalse);
    expect(ledger.pending, isEmpty);
    expect(ledger.problems, isEmpty);
  });

  test('a GitHub sign-in that creates an account fails and is reported for '
      'deletion by hand', () async {
    _project.oneAccountPerEmail = false;
    final (HarnessRun run, CleanupLedger ledger, _) = await _newRun(
      <String>[],
      githubAccountExists: true,
    );
    final StepResult result = await run.runStep(HarnessStep.github);
    expect(result.line(), 'FAIL github: new-account-created');
    expect(run.auth.currentUser, isNull);
    expect(ledger.problems.single, contains('new-github-user'));
  });

  test(
    'github already linked is only signed in with, and stays linked',
    () async {
      _project.githubLinked = true;
      final (HarnessRun run, CleanupLedger ledger, _) = await _newRun(
        <String>[],
      );
      final StepResult result = await run.runStep(HarnessStep.github);
      expect(result.status, StepStatus.pass, reason: result.line());
      expect(result.detail, contains('already linked'));
      expect(_project.githubLinked, isTrue);
      expect(ledger.pending, isEmpty);
    },
  );
}
