// The production verification kit of firebase_storage_dart: a command line tool that checks, against a real
// Cloud Storage for Firebase bucket, the behaviours the emulator cannot answer.
//
//     dart run test/production/verify_production.dart --backend=production --yes
//     dart run test/production/verify_production.dart --backend=emulator
//
// See tool/verify_production_storage/README.md (repository root) for the commands, the cost and how to read
// the report.
//
// The kit never reads, creates or prints credentials. A test user signs in with the email and password of the
// environment (FirebaseUserAuth), the tokens are only handed to the requests, and a session URI of a resumable
// upload (a bearer capability) is never printed. It writes only below one prefix that is unique to the run,
// counts the bytes it uploads against a cap, and deletes what it wrote.

// ignore_for_file: avoid_print, public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';
import 'package:http/http.dart' as http;

/// The outcome of a check.
enum Status {
  /// The behaviour was observed and is what the client relies on (or the question the check asks was answered;
  /// the answer is the first word of the summary).
  pass('PASS'),

  /// The client misbehaved, or the backend does something the client does not handle.
  fail('FAIL'),

  /// The check could not come to a result; the explanation says what to do.
  inconclusive('INCONCLUSIVE'),

  /// The check does not apply to this run.
  skipped('SKIPPED');

  const Status(this.label);

  final String label;
}

class CheckResult {
  CheckResult(
    this.status,
    this.summary, {
    this.details = const <String>[],
    this.observed = const <String, Object?>{},
  });

  final Status status;

  /// One line: what was observed.
  final String summary;

  /// More lines for the report.
  final List<String> details;

  /// Machine-readable observations (asserted by the emulator test of the kit).
  final Map<String, Object?> observed;
}

class Check {
  const Check(this.id, this.name, this.run);

  /// The id used with `--only`.
  final String id;
  final String name;
  final Future<CheckResult> Function(Kit kit) run;
}

/// The size cap would be exceeded by the next upload.
class ByteCapExceeded implements Exception {
  ByteCapExceeded(this.message);

  final String message;
}

/// The default of `--max-bytes`: 64 MiB.
const int defaultMaxBytes = 64 * 1024 * 1024;

/// The chunk granularity of a resumable upload.
const int chunkSize = 256 * 1024;

const String projectVariable = 'FIREBASE_TEST_PROJECT_ID';
const String bucketVariable = 'FIREBASE_TEST_STORAGE_BUCKET';
const String appIdVariable = 'FIREBASE_TEST_APP_ID';
const String webApiKeyVariable = 'FIREBASE_API_KEY';
const String emulatorHostVariable = 'FIREBASE_STORAGE_EMULATOR_HOST';
const String authEmulatorHostVariable = 'FIREBASE_AUTH_EMULATOR_HOST';

/// What the SDK's requests looked like: never a header value except the app id, never a URL query.
class Seen {
  Seen(this.method, this.path, this.status, this.headers);

  final String method;
  final String path;
  final int? status;

  /// The names of the headers that were sent, lower case, and the value of `x-firebase-gmpid`.
  final Map<String, String> headers;
}

/// The HTTP client of the SDK instances of the kit: records what was sent and can answer the first requests
/// with a 503 of its own, which never reaches the backend.
class KitClient extends http.BaseClient {
  KitClient(this._inner);

  final http.Client _inner;

  final List<Seen> seen = <Seen>[];

  /// How many of the next requests are answered with a simulated 503 without being sent.
  int faults = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Map<String, String> names = <String, String>{
      for (final MapEntry<String, String> entry in request.headers.entries)
        entry.key.toLowerCase(): entry.key.toLowerCase() == 'x-firebase-gmpid'
            ? entry.value
            : '',
    };
    final String path = request.url.path;
    if (faults > 0) {
      faults--;
      await request.finalize().drain<void>();
      seen.add(Seen(request.method, path, 503, names));
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('simulated by the kit')),
        503,
        request: request,
      );
    }
    final http.StreamedResponse response = await _inner.send(request);
    seen.add(Seen(request.method, path, response.statusCode, names));
    return response;
  }

  @override
  void close() => _inner.close();
}

/// An auth provider that first hands out a token the backend must refuse, and the real token once the client
/// asks for a refresh.
class StaleFirstAuth extends AuthTokenProvider {
  StaleFirstAuth(this._real);

  final AuthTokenProvider _real;
  final List<bool> calls = <bool>[];

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async {
    calls.add(forceRefresh);
    if (!forceRefresh) {
      return GetTokenResult('kit-not-a-valid-token');
    }
    return _real.getAccessToken(forceRefresh: true);
  }

  @override
  String? get uid => _real.uid;

  @override
  Stream<AuthTokenChange> get onTokenChanged => _real.onTokenChanged;
}

/// An App Check provider whose token is not one: a bucket that does not enforce App Check ignores it, one that
/// does refuses it.
class DummyAppCheck extends AppCheckTokenProvider {
  @override
  Future<AppCheckTokenResult> getToken({required bool forceRefresh}) async =>
      const AppCheckTokenResult('kit-not-an-app-check-token');

  @override
  Stream<AppCheckTokenResult> get onTokenChanged =>
      const Stream<AppCheckTokenResult>.empty();
}

/// Where the kit runs and how it signs in.
class Backend {
  Backend({
    required this.production,
    required this.projectId,
    required this.bucket,
    required this.deniedBucket,
    required this.emulatorHost,
    required this.appId,
    required this.apiKey,
  });

  final bool production;
  final String projectId;
  final String bucket;

  /// A bucket whose rules must refuse requests without a user, for the check of the 403 answer.
  final String? deniedBucket;

  /// The `host:port` of the emulator, null in production.
  final String? emulatorHost;
  final String appId;
  final String apiKey;

  String get label => production ? 'production' : 'emulator';
  String get origin => production
      ? 'https://firebasestorage.googleapis.com'
      : 'http://$emulatorHost';
}

/// What a check works with: the run's prefix, the byte budget, an SDK instance, raw HTTP and the clean-up list.
class Kit {
  Kit(
    this.backend,
    this.runId,
    this.maxBytes,
    this.out,
    this.environment,
    this.userAuth,
  ) : prefix = 'verify_storage_kit/$runId';

  final Backend backend;
  final String runId;
  final int maxBytes;
  final StringSink out;
  final Map<String, String> environment;

  /// The signed-in test user, or null for requests without a user.
  final FirebaseUserAuth? userAuth;

  /// The only place the kit writes: `verify_storage_kit/run_<utc>_<suffix>`.
  final String prefix;

  int uploadedBytes = 0;
  final List<(String bucket, String name)> written = <(String, String)>[];
  final List<http.Client> _clients = <http.Client>[];
  int _appCount = 0;

  /// The metadata name under the run's prefix.
  String name(String relative) => '$prefix/$relative';

  /// Counts [bytes] against the cap; throws [ByteCapExceeded] before the upload that would pass it.
  void charge(int bytes) {
    if (uploadedBytes + bytes > maxBytes) {
      throw ByteCapExceeded(
        'uploading $bytes more bytes would pass the cap of $maxBytes bytes '
        '($uploadedBytes used).',
      );
    }
    uploadedBytes += bytes;
  }

  /// Remembers that [objectName] may exist now, for the clean-up.
  void track(String objectName, {String? bucket}) =>
      written.add((bucket ?? backend.bucket, objectName));

  /// Deterministic bytes: the same [seed] and [length] give the same data.
  static Uint8List bytes(int length, int seed) {
    final math.Random random = math.Random(seed);
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static String md5Base64(List<int> data) =>
      base64.encode(crypto.md5.convert(data).bytes);

  /// A fresh app, with the user's token provider when there is a user, and a storage over a recording client.
  ({FirebaseApp app, FirebaseStorage storage, KitClient client}) newStorage({
    AuthTokenProvider? auth,
    AppCheckTokenProvider? appCheck,
    bool signedIn = true,
    StorageRetryPolicy retry = const StorageRetryPolicy(
      operation: Duration(seconds: 30),
      upload: Duration(seconds: 60),
      download: Duration(seconds: 60),
    ),
  }) {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: backend.apiKey,
        appId: backend.appId,
        projectId: backend.projectId,
        storageBucket: backend.bucket,
      ),
      name: 'verify-storage-${runId}_${_appCount++}',
    );
    final AuthTokenProvider? provider = auth ?? (signedIn ? userAuth : null);
    if (provider != null) {
      app.authProvider = provider;
    }
    if (appCheck != null) {
      app.appCheckProvider = appCheck;
    }
    final KitClient client = KitClient(http.Client());
    return (
      app: app,
      storage: FirebaseStorage(
        app,
        emulatorHost: backend.emulatorHost,
        httpClient: client,
        retry: retry,
      ),
      client: client,
    );
  }

  /// A plain client for the raw requests; closed with the kit.
  http.Client newRawClient() {
    final http.Client client = http.Client();
    _clients.add(client);
    return client;
  }

  /// The `Authorization` header of the test user, or nothing without one. Never printed.
  Future<Map<String, String>> authHeaders() async {
    final FirebaseUserAuth? auth = userAuth;
    if (auth == null) {
      return const <String, String>{};
    }
    final GetTokenResult token = await auth.getAccessToken(forceRefresh: false);
    return <String, String>{'Authorization': 'Firebase ${token.token}'};
  }

  /// The URL of the bucket's objects: `<origin>/v0/b/<bucket>/o`.
  Uri bucketUrl({String? bucket, Map<String, String>? query}) => Uri.parse(
    '${backend.origin}/v0/b/${bucket ?? backend.bucket}/o',
  ).replace(queryParameters: query);

  /// The URL of one object (`alt=media` for its content).
  Uri objectUrl(String objectName, {bool media = false, String? bucket}) =>
      Uri.parse(
        '${backend.origin}/v0/b/${bucket ?? backend.bucket}/o/'
        '${Uri.encodeComponent(objectName)}${media ? '?alt=media' : ''}',
      );

  /// A raw request. [user] adds the test user's token; the SDK's `X-Firebase-GMPID` is added unless
  /// [gmpid] is false.
  Future<http.Response> raw(
    http.Client client,
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    List<int>? body,
    bool user = true,
    bool gmpid = true,
  }) async {
    final http.Request request = http.Request(method, url)
      ..headers.addAll(<String, String>{
        if (gmpid) 'X-Firebase-GMPID': backend.appId,
        if (user) ...await authHeaders(),
        ...headers,
      });
    if (body != null) {
      request.bodyBytes = body;
    }
    return http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 90)),
    );
  }

  /// Uploads [data] with a multipart request of the SDK and tracks the object.
  Future<FullMetadata> put(
    FirebaseStorage storage,
    String relative,
    Uint8List data, {
    String contentType = 'application/octet-stream',
  }) async {
    charge(data.length);
    final String objectName = name(relative);
    track(objectName);
    return storage
        .ref(objectName)
        .putBytes(data, metadata: SettableMetadata(contentType: contentType));
  }

  /// Deletes every object the run could have written; returns how many deletes succeeded or found nothing.
  Future<int> cleanUp() async {
    final http.Client client = newRawClient();
    final Set<(String, String)> targets = <(String, String)>{...written};
    String? pageToken;
    do {
      final http.Response page = await raw(
        client,
        'GET',
        bucketUrl(
          query: <String, String>{
            'prefix': '$prefix/',
            'maxResults': '1000',
            'pageToken': ?pageToken,
          },
        ),
      );
      if (page.statusCode != 200) {
        throw StateError(
          'listing $prefix/ answered HTTP ${page.statusCode}: ${_clip(page.body)}',
        );
      }
      final Map<String, Object?> json =
          jsonDecode(page.body) as Map<String, Object?>;
      for (final Object? item
          in (json['items'] as List<Object?>?) ?? const []) {
        targets.add((
          backend.bucket,
          (item! as Map<String, Object?>)['name']! as String,
        ));
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    int deleted = 0;
    final List<String> failures = <String>[];
    for (final (String bucket, String objectName) in targets) {
      final http.Response response = await raw(
        client,
        'DELETE',
        objectUrl(objectName, bucket: bucket),
      );
      if (response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404) {
        deleted++;
      } else if (bucket != backend.bucket && response.statusCode == 403) {
        deleted++; // refused: it was never written
      } else {
        failures.add('$bucket/$objectName: HTTP ${response.statusCode}');
      }
    }
    if (failures.isNotEmpty) {
      throw StateError('could not delete ${failures.join(', ')}');
    }
    return deleted;
  }

  Future<void> close() async {
    for (final http.Client client in _clients) {
      client.close();
    }
  }
}

String _clip(String text) =>
    text.length <= 160 ? text : '${text.substring(0, 160)}...';

String _describe(Object error) {
  if (error is FirebaseStorageException) {
    return '${error.code} (HTTP ${error.httpStatus})';
  }
  return '${error.runtimeType}: ${_clip('$error')}';
}

/// The JSON error envelope `{"error": {"code": N, "message": ...}}`, or null when the body is something else.
({int code, String message})? _envelope(String body) {
  try {
    final Object? json = jsonDecode(body);
    if (json is Map<String, Object?> && json['error'] is Map<String, Object?>) {
      final Map<String, Object?> error = json['error']! as Map<String, Object?>;
      final Object? code = error['code'];
      if (code is int) {
        return (code: code, message: '${error['message']}');
      }
    }
  } on FormatException {
    return null;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------
// The checks.

Future<CheckResult> _error404(Kit kit) async {
  final http.Client client = kit.newRawClient();
  final http.Response response = await kit.raw(
    client,
    'GET',
    kit.objectUrl(kit.name('does_not_exist.txt')),
  );
  final String type = response.headers['content-type'] ?? 'no content-type';
  final ({int code, String message})? envelope = _envelope(response.body);
  final storage = kit.newStorage();
  String sdk;
  try {
    await storage.storage.ref(kit.name('does_not_exist.txt')).metadata();
    sdk = 'no error';
  } on FirebaseStorageException catch (e) {
    sdk =
        '${e.code} / HTTP ${e.httpStatus} / body kept: ${(e.serverResponse ?? '').isNotEmpty}';
  } finally {
    storage.storage.close();
  }
  final Map<String, Object?> observed = <String, Object?>{
    'status': response.statusCode,
    'envelope': envelope != null,
    'sdk': sdk.split(' ').first,
  };
  if (response.statusCode != 404 ||
      sdk.split(' ').first != 'object-not-found') {
    return CheckResult(
      Status.fail,
      'A missing object answered HTTP ${response.statusCode} and the SDK reported $sdk.',
      observed: observed,
    );
  }
  if (envelope != null) {
    return CheckResult(
      Status.pass,
      'JSON ENVELOPE: HTTP 404, {"error": {"code": ${envelope.code}, "message": "${_clip(envelope.message)}"}}; '
      'the SDK reports $sdk.',
      details: <String>['content-type: $type'],
      observed: observed,
    );
  }
  return CheckResult(
    kit.backend.production ? Status.fail : Status.inconclusive,
    'PLAIN BODY: HTTP 404 with a body that is not a JSON envelope (${_clip(response.body)}); the SDK reports $sdk.',
    details: <String>[
      'content-type: $type',
      if (!kit.backend.production)
        'The emulator answers differently from production here; the SDK maps by status, so it is not affected.',
    ],
    observed: observed,
  );
}

Future<CheckResult> _error403(Kit kit) async {
  final String? denied = kit.backend.deniedBucket;
  if (denied == null) {
    return CheckResult(
      Status.skipped,
      'No --denied-bucket: name a bucket whose rules refuse requests without a user to run this.',
    );
  }
  final http.Client client = kit.newRawClient();
  final String objectName = kit.name('denied.txt');
  kit.track(objectName, bucket: denied);
  final Uri upload = kit.bucketUrl(
    bucket: denied,
    query: <String, String>{'name': objectName},
  );
  final http.Response write = await kit.raw(
    client,
    'POST',
    upload,
    headers: <String, String>{'Content-Type': 'text/plain'},
    body: utf8.encode('x'),
    user: false,
  );
  final http.Response read = await kit.raw(
    client,
    'GET',
    kit.objectUrl(objectName, bucket: denied),
    user: false,
  );
  final ({int code, String message})? envelope = _envelope(write.body);
  final Map<String, Object?> observed = <String, Object?>{
    'writeStatus': write.statusCode,
    'readStatus': read.statusCode,
    'envelope': envelope != null,
  };
  if (write.statusCode >= 200 && write.statusCode < 300) {
    return CheckResult(
      Status.fail,
      'The write without a user was accepted (HTTP ${write.statusCode}): $denied does not refuse it.',
      observed: observed,
    );
  }
  final String code = write.statusCode == 403
      ? 'unauthorized'
      : 'unauthenticated';
  final storage = kit.newStorage(signedIn: false);
  String sdk;
  try {
    await storage.storage.refFromUrl('gs://$denied/$objectName').metadata();
    sdk = 'no error';
  } on FirebaseStorageException catch (e) {
    sdk = e.code;
  } finally {
    storage.storage.close();
  }
  observed['sdk'] = sdk;
  final bool ok = write.statusCode == 403 && sdk == code && envelope != null;
  return CheckResult(
    ok ? Status.pass : Status.fail,
    '${write.statusCode == 403 ? 'DENIED' : 'REFUSED'}: the write without a user answered '
    'HTTP ${write.statusCode} ${envelope != null ? 'with a JSON envelope' : 'with a plain body (${_clip(write.body)})'}, '
    'the read HTTP ${read.statusCode}; the SDK reports $sdk.',
    details: <String>[
      if (!ok) 'Expected HTTP 403, a JSON envelope and the SDK code $code.',
    ],
    observed: observed,
  );
}

Future<CheckResult> _range(Kit kit) async {
  final Uint8List data = Kit.bytes(1024, 3);
  final storage = kit.newStorage();
  try {
    await kit.put(storage.storage, 'range.bin', data);
  } finally {
    storage.storage.close();
  }
  final http.Client client = kit.newRawClient();
  final Uri url = kit.objectUrl(kit.name('range.bin'), media: true);
  final http.Response part = await kit.raw(
    client,
    'GET',
    url,
    headers: <String, String>{'Range': 'bytes=10-19'},
  );
  final http.Response beyond = await kit.raw(
    client,
    'GET',
    url,
    headers: <String, String>{'Range': 'bytes=5000-5009'},
  );
  final Map<String, Object?> observed = <String, Object?>{
    'status': part.statusCode,
    'bytes': part.bodyBytes.length,
    'contentRange': part.headers['content-range'],
    'beyondStatus': beyond.statusCode,
  };
  final bool honoured =
      part.statusCode == 206 &&
      part.bodyBytes.length == 10 &&
      _same(part.bodyBytes, data.sublist(10, 20));
  final bool ignored = part.statusCode == 200 && _same(part.bodyBytes, data);
  if (!honoured && !ignored) {
    return CheckResult(
      Status.fail,
      'Range: bytes=10-19 answered HTTP ${part.statusCode} with ${part.bodyBytes.length} bytes that are not the requested ones.',
      observed: observed,
    );
  }
  return CheckResult(
    Status.pass,
    '${honoured ? 'HONOURED' : 'IGNORED'}: Range: bytes=10-19 answered HTTP ${part.statusCode} with '
    '${part.bodyBytes.length} bytes (content-range: ${part.headers['content-range'] ?? 'none'}); '
    'a range past the end answered HTTP ${beyond.statusCode}.',
    details: <String>[
      if (ignored)
        'The backend sends the whole object; a client that resumes a download must check for 206.',
    ],
    observed: observed,
  );
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

Future<CheckResult> _downloadToken(Kit kit) async {
  final Uint8List data = Kit.bytes(2048, 4);
  final storage = kit.newStorage();
  try {
    final FullMetadata metadata = await kit.put(
      storage.storage,
      'token.bin',
      data,
    );
    final Reference ref = storage.storage.ref(kit.name('token.bin'));
    final String url;
    try {
      url = await ref.downloadUrl();
    } on FirebaseStorageException catch (e) {
      return CheckResult(
        Status.fail,
        'The uploaded object has no usable download URL: ${_describe(e)}.',
        observed: <String, Object?>{'tokens': metadata.downloadTokens.length},
      );
    }
    final Uri parsed = Uri.parse(url);
    final String token = parsed.queryParameters['token'] ?? '';
    final http.Client client = kit.newRawClient();
    final http.Response withToken = await kit.raw(
      client,
      'GET',
      parsed,
      user: false,
      gmpid: false,
    );
    final http.Response wrongToken = await kit.raw(
      client,
      'GET',
      parsed.replace(
        queryParameters: <String, String>{
          'alt': 'media',
          'token': 'wrong-${token.length}',
        },
      ),
      user: false,
      gmpid: false,
    );
    final Map<String, Object?> observed = <String, Object?>{
      'tokens': metadata.downloadTokens.length,
      'tokenLength': token.length,
      'status': withToken.statusCode,
      'wrongTokenStatus': wrongToken.statusCode,
    };
    final bool ok =
        withToken.statusCode == 200 && _same(withToken.bodyBytes, data);
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'A new object has ${metadata.downloadTokens.length} download token(s) (${token.length} characters); '
                'the download URL served the bytes without credentials (HTTP 200); a wrong token answered '
                'HTTP ${wrongToken.statusCode}.'
          : 'The download URL answered HTTP ${withToken.statusCode} with ${withToken.bodyBytes.length} bytes.',
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

Future<CheckResult> _listPaging(Kit kit) async {
  final storage = kit.newStorage();
  try {
    final Uint8List small = Kit.bytes(64, 5);
    for (final String relative in <String>[
      'list/a.txt',
      'list/b.txt',
      'list/c.txt',
      'list/sub/d.txt',
    ]) {
      await kit.put(storage.storage, relative, small);
    }
    final Reference folder = storage.storage.ref(kit.name('list'));
    final ListResult first = await folder.list(maxResults: 2);
    final String token = first.nextPageToken ?? '';
    if (token.isEmpty) {
      return CheckResult(
        Status.fail,
        'A page of 2 out of 3 items and 1 prefix came back without a nextPageToken '
        '(${first.items.length} items, ${first.prefixes.length} prefixes).',
      );
    }
    final Set<String> entries = <String>{
      for (final Reference r in first.items) r.fullPath,
      for (final Reference r in first.prefixes) r.fullPath,
    };
    final List<int> pageSizes = <int>[
      first.items.length + first.prefixes.length,
    ];
    String? next = token;
    while (next != null && next.isNotEmpty && pageSizes.length < 10) {
      final ListResult page = await folder.list(maxResults: 2, pageToken: next);
      entries.addAll(<String>[
        for (final Reference r in page.items) r.fullPath,
        for (final Reference r in page.prefixes) r.fullPath,
      ]);
      pageSizes.add(page.items.length + page.prefixes.length);
      next = page.nextPageToken;
    }
    final ListResult all = await folder.listAll();
    final String shape = RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(token)
        ? 'URL-safe characters'
        : RegExp(r'^[A-Za-z0-9+/=_\-]+$').hasMatch(token)
        ? 'base64 characters'
        : 'other characters';
    final Map<String, Object?> observed = <String, Object?>{
      'pages': pageSizes.length,
      'entries': entries.length,
      'tokenCharacters': shape,
      'allItems': all.items.length,
      'allPrefixes': all.prefixes.length,
    };
    final bool ok =
        entries.length == 4 &&
        all.items.length == 3 &&
        all.prefixes.length == 1 &&
        (next == null || next.isEmpty);
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? '${pageSizes.length} pages of at most 2 ($pageSizes entries each, a prefix may repeat) covered 3 items and '
                '1 prefix; the token has ${token.length} $shape and the last page has none; listAll found '
                '${all.items.length} items and ${all.prefixes.length} prefix.'
          : 'Paging covered ${entries.length} distinct entries in pages of $pageSizes (expected 4), listAll '
                '${all.items.length} items and ${all.prefixes.length} prefixes.',
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

Future<CheckResult> _multipart(Kit kit) async {
  final Uint8List data = Kit.bytes(4096, 6);
  final storage = kit.newStorage();
  try {
    final FullMetadata metadata = await kit.put(
      storage.storage,
      'multipart.bin',
      data,
      contentType: 'application/x-verify',
    );
    final Map<String, Object?> observed = <String, Object?>{
      'size': metadata.size,
      'contentType': metadata.contentType,
      'md5Matches': metadata.md5Hash == Kit.md5Base64(data),
    };
    final bool ok =
        metadata.size == data.length &&
        metadata.contentType == 'application/x-verify' &&
        metadata.md5Hash == Kit.md5Base64(data);
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'MULTIPART: one request stored ${metadata.size} bytes with content type ${metadata.contentType}; '
                'the backend md5Hash equals the local one.'
          : 'The multipart upload returned size ${metadata.size}, content type ${metadata.contentType}, md5 match '
                '${observed['md5Matches']}.',
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

/// The result of starting a resumable session: the URI is a bearer capability and is never printed.
class Session {
  Session(this.uri, this.status, this.granularity);

  final Uri uri;
  final String status;
  final int? granularity;
}

Future<Session> _startResumable(
  Kit kit,
  http.Client client,
  String objectName,
  int length, {
  Map<String, String> extra = const {},
}) async {
  final http.Response response = await kit.raw(
    client,
    'POST',
    kit.bucketUrl(query: <String, String>{'name': objectName}),
    headers: <String, String>{
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': '$length',
      'X-Goog-Upload-Header-Content-Type': 'application/octet-stream',
      'Content-Type': 'application/json; charset=utf-8',
      ...extra,
    },
    body: utf8.encode(
      jsonEncode(<String, Object?>{
        'name': objectName,
        'contentType': 'application/octet-stream',
      }),
    ),
  );
  final String? url = response.headers['x-goog-upload-url'];
  if (response.statusCode != 200 || url == null) {
    throw StateError(
      'starting a resumable upload answered HTTP ${response.statusCode}: ${_clip(response.body)}',
    );
  }
  return Session(
    Uri.parse(url),
    response.headers['x-goog-upload-status'] ?? 'missing',
    int.tryParse(response.headers['x-goog-upload-chunk-granularity'] ?? ''),
  );
}

Future<http.Response> _sendChunk(
  Kit kit,
  http.Client client,
  Session session,
  Uint8List data,
  int offset,
  int length, {
  required bool last,
}) {
  return kit.raw(
    client,
    'POST',
    session.uri,
    headers: <String, String>{
      'X-Goog-Upload-Command': last ? 'upload, finalize' : 'upload',
      'X-Goog-Upload-Offset': '$offset',
      'Content-Type': 'application/octet-stream',
    },
    body: data.sublist(offset, offset + length),
    user: false,
    gmpid: false,
  );
}

Future<http.Response> _query(Kit kit, http.Client client, Session session) =>
    kit.raw(
      client,
      'POST',
      session.uri,
      headers: <String, String>{'X-Goog-Upload-Command': 'query'},
      user: false,
      gmpid: false,
    );

Future<void> _cancel(Kit kit, http.Client client, Session session) => kit.raw(
  client,
  'POST',
  session.uri,
  headers: <String, String>{'X-Goog-Upload-Command': 'cancel'},
  user: false,
  gmpid: false,
);

/// Sends the rest of [data] from [offset] in chunks and returns the last response.
Future<http.Response> _finish(
  Kit kit,
  http.Client client,
  Session session,
  Uint8List data,
  int offset,
) async {
  http.Response? last;
  int at = offset;
  while (at < data.length) {
    final int length = math.min(chunkSize, data.length - at);
    final bool final_ = at + length == data.length;
    last = await _sendChunk(
      kit,
      client,
      session,
      data,
      at,
      length,
      last: final_,
    );
    if (last.statusCode != 200) {
      return last;
    }
    at += length;
  }
  return last ??
      await _sendChunk(kit, client, session, data, data.length, 0, last: true);
}

bool _stored(http.Response response, Uint8List data) {
  if (response.statusCode != 200 ||
      response.headers['x-goog-upload-status'] != 'final') {
    return false;
  }
  try {
    final Map<String, Object?> json =
        jsonDecode(response.body) as Map<String, Object?>;
    return json['size'] == '${data.length}' &&
        json['md5Hash'] == Kit.md5Base64(data);
  } on Object {
    return false;
  }
}

Future<CheckResult> _resumable(Kit kit) async {
  final Uint8List data = Kit.bytes(3 * chunkSize, 7);
  final String objectName = kit.name('resumable.bin');
  kit.charge(data.length);
  kit.track(objectName);
  final http.Client client = kit.newRawClient();
  final Session session = await _startResumable(
    kit,
    client,
    objectName,
    data.length,
  );
  final List<String> statuses = <String>[];
  http.Response? last;
  for (int i = 0; i < 3; i++) {
    last = await _sendChunk(
      kit,
      client,
      session,
      data,
      i * chunkSize,
      chunkSize,
      last: i == 2,
    );
    statuses.add(
      '${last.statusCode}/${last.headers['x-goog-upload-status'] ?? 'none'}',
    );
    if (last.statusCode != 200) {
      return CheckResult(
        Status.fail,
        'Chunk ${i + 1} of 3 answered HTTP ${last.statusCode}: ${_clip(last.body)}',
        observed: <String, Object?>{'chunks': statuses},
      );
    }
  }
  final bool ok = session.status == 'active' && _stored(last!, data);
  return CheckResult(
    ok ? Status.pass : Status.fail,
    ok
        ? 'RESUMABLE: start answered x-goog-upload-status: active (granularity ${session.granularity ?? 'not sent'}); '
              '3 chunks of $chunkSize bytes ended with final and the stored size and md5 match.'
        : 'The session ended with start status ${session.status} and chunk answers $statuses; the stored object does not match.',
    observed: <String, Object?>{
      'startStatus': session.status,
      'granularity': session.granularity,
      'chunks': statuses,
    },
  );
}

Future<CheckResult> _pauseResume(Kit kit) async {
  final Uint8List data = Kit.bytes(4 * chunkSize, 8);
  final String objectName = kit.name('paused.bin');
  kit.charge(data.length + chunkSize);
  kit.track(objectName);
  final http.Client client = kit.newRawClient();
  final Session session = await _startResumable(
    kit,
    client,
    objectName,
    data.length,
  );
  final http.Response first = await _sendChunk(
    kit,
    client,
    session,
    data,
    0,
    chunkSize,
    last: false,
  );
  if (first.statusCode != 200) {
    return CheckResult(
      Status.fail,
      'The first chunk answered HTTP ${first.statusCode}.',
    );
  }
  // Pause: abort the second chunk in flight.
  final Completer<void> abort = Completer<void>();
  final http.AbortableStreamedRequest request =
      http.AbortableStreamedRequest(
          'POST',
          session.uri,
          abortTrigger: abort.future,
        )
        ..headers.addAll(<String, String>{
          'X-Goog-Upload-Command': 'upload',
          'X-Goog-Upload-Offset': '$chunkSize',
          'Content-Type': 'application/octet-stream',
        })
        ..contentLength = 2 * chunkSize;
  final Future<http.StreamedResponse> inFlight = kit.newRawClient().send(
    request,
  );
  request.sink.add(data.sublist(chunkSize, chunkSize + chunkSize ~/ 2));
  await Future<void>.delayed(const Duration(milliseconds: 100));
  abort.complete();
  String pause;
  try {
    final http.StreamedResponse done = await inFlight;
    await done.stream.drain<void>();
    pause = 'the chunk was answered before the abort (HTTP ${done.statusCode})';
  } on http.RequestAbortedException {
    pause = 'the second chunk was aborted in flight';
  }
  final http.Response status = await _query(kit, client, session);
  final int received =
      int.tryParse(status.headers['x-goog-upload-size-received'] ?? '') ?? -1;
  final Map<String, Object?> observed = <String, Object?>{
    'pause': pause,
    'queryStatus': status.headers['x-goog-upload-status'],
    'received': received,
  };
  if (status.statusCode != 200 ||
      received < chunkSize ||
      received > 3 * chunkSize) {
    return CheckResult(
      Status.fail,
      'After the pause the query answered HTTP ${status.statusCode}, status ${status.headers['x-goog-upload-status']}, '
      'size received $received (expected a multiple of $chunkSize from $chunkSize).',
      observed: observed,
    );
  }
  final http.Response end = await _finish(kit, client, session, data, received);
  final bool ok = _stored(end, data);
  return CheckResult(
    ok ? Status.pass : Status.fail,
    ok
        ? 'RESUMED at $received of ${data.length} bytes after a pause ($pause); the query said '
              'x-goog-upload-status: ${status.headers['x-goog-upload-status']}; the stored size and md5 match.'
        : 'Resuming at $received ended with HTTP ${end.statusCode}: ${_clip(end.body)}',
    observed: observed,
  );
}

Future<CheckResult> _resumeBySessionUri(Kit kit) async {
  final Uint8List data = Kit.bytes(3 * chunkSize, 9);
  final String objectName = kit.name('session.bin');
  kit.charge(data.length);
  kit.track(objectName);
  final Session session = await _startResumable(
    kit,
    kit.newRawClient(),
    objectName,
    data.length,
  );
  final http.Response first = await _sendChunk(
    kit,
    kit.newRawClient(),
    session,
    data,
    0,
    chunkSize,
    last: false,
  );
  if (first.statusCode != 200) {
    return CheckResult(
      Status.fail,
      'The first chunk answered HTTP ${first.statusCode}.',
    );
  }
  // A new connection that knows nothing but the session URI, as after a restart of the app.
  final http.Client fresh = kit.newRawClient();
  final Session knownOnlyByUri = Session(session.uri, 'unknown', null);
  final http.Response status = await _query(kit, fresh, knownOnlyByUri);
  final int received =
      int.tryParse(status.headers['x-goog-upload-size-received'] ?? '') ?? -1;
  if (status.statusCode != 200 || received != chunkSize) {
    return CheckResult(
      Status.fail,
      'A new client querying the session URI got HTTP ${status.statusCode}, size received $received (expected $chunkSize).',
      observed: <String, Object?>{'received': received},
    );
  }
  final http.Response end = await _finish(
    kit,
    fresh,
    knownOnlyByUri,
    data,
    received,
  );
  final bool ok = _stored(end, data);
  return CheckResult(
    ok ? Status.pass : Status.fail,
    ok
        ? 'RESUMED by session URI: a new connection queried $received received bytes and finished the upload; the '
              'stored size and md5 match.'
        : 'Finishing by session URI ended with HTTP ${end.statusCode}: ${_clip(end.body)}',
    observed: <String, Object?>{'received': received},
  );
}

Future<CheckResult> _md5(Kit kit) async {
  final Uint8List data = Kit.bytes(2048, 10);
  final String good = kit.name('md5_good.bin');
  final String bad = kit.name('md5_bad.bin');
  kit.charge(data.length * 2);
  kit.track(good);
  kit.track(bad);
  final http.Client client = kit.newRawClient();
  Future<http.Response> upload(String objectName, String md5) async {
    const String boundary = 'verify_storage_kit_boundary';
    final BytesBuilder body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=utf-8\r\n\r\n',
        ),
      )
      ..add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'name': objectName,
            'contentType': 'application/octet-stream',
            'md5Hash': md5,
          }),
        ),
      )
      ..add(
        utf8.encode(
          '\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n',
        ),
      )
      ..add(data)
      ..add(utf8.encode('\r\n--$boundary--'));
    return kit.raw(
      client,
      'POST',
      kit.bucketUrl(query: <String, String>{'name': objectName}),
      headers: <String, String>{
        'X-Goog-Upload-Protocol': 'multipart',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body.takeBytes(),
    );
  }

  final String right = Kit.md5Base64(data);
  final http.Response accepted = await upload(good, right);
  final http.Response mismatch = await upload(
    bad,
    Kit.md5Base64(<int>[...data, 1]),
  );
  final Map<String, Object?> observed = <String, Object?>{
    'matchingStatus': accepted.statusCode,
    'wrongStatus': mismatch.statusCode,
  };
  if (accepted.statusCode != 200) {
    return CheckResult(
      Status.fail,
      'An upload with the right md5Hash answered HTTP ${accepted.statusCode}: ${_clip(accepted.body)}',
      observed: observed,
    );
  }
  final bool rejected = mismatch.statusCode >= 400;
  String stored = '';
  if (!rejected) {
    final Object? json = jsonDecode(mismatch.body);
    stored = json is Map<String, Object?> && json['md5Hash'] == right
        ? 'the stored md5Hash is the real one of the bytes'
        : 'the stored md5Hash is not the real one of the bytes';
  }
  observed['rejected'] = rejected;
  return CheckResult(
    Status.pass,
    rejected
        ? 'VERIFIED: an md5Hash that does not match the bytes was rejected (HTTP ${mismatch.statusCode}, ${_envelope(mismatch.body)?.message ?? _clip(mismatch.body)}); '
              'the right one was accepted.'
        : 'NOT VERIFIED: an md5Hash that does not match the bytes was accepted (HTTP ${mismatch.statusCode}); $stored. '
              'A client that wants integrity has to compare the returned md5Hash itself.',
    observed: observed,
  );
}

Future<CheckResult> _appCheck(Kit kit) async {
  final Uint8List data = Kit.bytes(256, 11);
  final plain = kit.newStorage();
  try {
    await kit.put(plain.storage, 'appcheck.bin', data);
  } finally {
    plain.storage.close();
  }
  final dummy = kit.newStorage(appCheck: DummyAppCheck());
  try {
    String outcome;
    String code;
    try {
      await dummy.storage.ref(kit.name('appcheck.bin')).metadata();
      outcome = 'ACCEPTED';
      code = 'ok';
    } on FirebaseStorageException catch (e) {
      code = e.code;
      outcome = e.code == 'unauthorized-app' ? 'ENFORCED' : 'REFUSED';
    }
    final bool sent = dummy.client.seen.any(
      (Seen s) => s.headers.containsKey('x-firebase-appcheck'),
    );
    final Map<String, Object?> observed = <String, Object?>{
      'outcome': outcome,
      'code': code,
      'headerSent': sent,
    };
    if (!sent || outcome == 'REFUSED') {
      return CheckResult(
        Status.fail,
        outcome == 'REFUSED'
            ? 'A request with an App Check token that is not valid was refused with $code, not unauthorized-app.'
            : 'The X-Firebase-AppCheck header was not sent.',
        observed: observed,
      );
    }
    return CheckResult(
      Status.pass,
      outcome == 'ACCEPTED'
          ? 'ACCEPTED: the X-Firebase-AppCheck header was sent and the bucket does not enforce App Check (HTTP 200 with a token that is not valid).'
          : 'ENFORCED: the bucket refused a token that is not valid, and the SDK reports unauthorized-app.',
      details: <String>[
        'A real App Check token is not covered: the kit has no App Check token provider.',
      ],
      observed: observed,
    );
  } finally {
    dummy.storage.close();
  }
}

Future<CheckResult> _gmpid(Kit kit) async {
  final storage = kit.newStorage();
  try {
    await kit.put(storage.storage, 'gmpid.bin', Kit.bytes(64, 12));
    await storage.storage.ref(kit.name('gmpid.bin')).metadata();
    final List<Seen> sdkSeen = storage.client.seen;
    final bool allSent =
        sdkSeen.isNotEmpty &&
        sdkSeen.every(
          (Seen s) => s.headers['x-firebase-gmpid'] == kit.backend.appId,
        );
    final http.Response without = await kit.raw(
      kit.newRawClient(),
      'GET',
      kit.objectUrl(kit.name('gmpid.bin')),
      gmpid: false,
    );
    final Map<String, Object?> observed = <String, Object?>{
      'allSent': allSent,
      'requests': sdkSeen.length,
      'withoutStatus': without.statusCode,
    };
    return CheckResult(
      allSent ? Status.pass : Status.fail,
      allSent
          ? 'SENT: X-Firebase-GMPID carried the app id on all ${sdkSeen.length} requests of the SDK and they were served; '
                'the same read without the header answered HTTP ${without.statusCode}.'
          : 'X-Firebase-GMPID was missing or wrong on some of the SDK requests.',
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

Future<CheckResult> _refresh401(Kit kit) async {
  final FirebaseUserAuth? user = kit.userAuth;
  if (user == null) {
    return CheckResult(
      Status.skipped,
      'No throwaway user (--create-user with $webApiKeyVariable or --api-key=): a refresh needs a user.',
    );
  }
  final Uint8List data = Kit.bytes(128, 13);
  final plain = kit.newStorage();
  try {
    await kit.put(plain.storage, 'refresh.bin', data);
  } finally {
    plain.storage.close();
  }
  final StaleFirstAuth stale = StaleFirstAuth(user);
  final stored = kit.newStorage(auth: stale);
  try {
    final FullMetadata metadata = await stored.storage
        .ref(kit.name('refresh.bin'))
        .metadata();
    final List<int?> statuses = <int?>[
      for (final Seen s in stored.client.seen) s.status,
    ];
    final Map<String, Object?> observed = <String, Object?>{
      'calls': stale.calls,
      'statuses': statuses,
      'size': metadata.size,
    };
    if (statuses.isNotEmpty && statuses.first != 401) {
      return CheckResult(
        Status.inconclusive,
        'The backend answered HTTP ${statuses.first} to a token it should refuse, not 401, so no refresh was provoked.',
        observed: observed,
      );
    }
    final bool ok =
        statuses.length == 2 &&
        statuses.first == 401 &&
        statuses.last == 200 &&
        stale.calls.length == 2 &&
        !stale.calls.first &&
        stale.calls.last;
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'REFRESHED: a token the backend refused answered HTTP 401, the SDK asked for a new token '
                '(forceRefresh) and the retry was served (HTTP 200).'
          : 'The statuses were $statuses and the token requests (forceRefresh) $stale.calls; expected 401 then 200.',
      observed: observed,
    );
  } on FirebaseStorageException catch (e) {
    return CheckResult(
      Status.fail,
      'The request with a stale token failed with ${_describe(e)}; the statuses were '
      '${<int?>[for (final Seen s in stored.client.seen) s.status]}.',
      observed: <String, Object?>{'calls': stale.calls},
    );
  } finally {
    stored.storage.close();
  }
}

Future<CheckResult> _cors(Kit kit) async {
  final http.Client client = kit.newRawClient();
  const String origin = 'https://verify-storage-kit.invalid';
  final Uint8List data = Kit.bytes(chunkSize, 14);
  final String objectName = kit.name('cors.bin');
  kit.track(objectName);
  final http.Response preflight = await kit.raw(
    client,
    'OPTIONS',
    kit.bucketUrl(query: <String, String>{'name': objectName}),
    headers: <String, String>{
      'Origin': origin,
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers':
          'x-goog-upload-command,x-goog-upload-protocol,x-goog-upload-offset,content-type,x-firebase-gmpid,x-firebase-storage-version',
    },
    user: false,
    gmpid: false,
  );
  final http.Response start = await kit.raw(
    client,
    'POST',
    kit.bucketUrl(query: <String, String>{'name': objectName}),
    headers: <String, String>{
      'Origin': origin,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': '${data.length}',
      'X-Goog-Upload-Header-Content-Type': 'application/octet-stream',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: utf8.encode(jsonEncode(<String, Object?>{'name': objectName})),
  );
  final String? url = start.headers['x-goog-upload-url'];
  if (url != null) {
    await _cancel(kit, client, Session(Uri.parse(url), 'active', null));
  }
  final String exposed = (start.headers['access-control-expose-headers'] ?? '')
      .toLowerCase();
  final String allowOrigin = start.headers['access-control-allow-origin'] ?? '';
  final String allowHeaders =
      (preflight.headers['access-control-allow-headers'] ?? '').toLowerCase();
  const List<String> needed = <String>[
    'x-goog-upload-url',
    'x-goog-upload-status',
    'x-goog-upload-size-received',
  ];
  final List<String> missingExposed = <String>[
    for (final String h in needed)
      if (!exposed.contains(h) && exposed != '*') h,
  ];
  final List<String> missingAllowed = <String>[
    for (final String h in <String>[
      'x-goog-upload-command',
      'x-goog-upload-protocol',
      'x-goog-upload-offset',
    ])
      if (!allowHeaders.contains(h) && allowHeaders != '*') h,
  ];
  final bool originOk = allowOrigin == '*' || allowOrigin == origin;
  final Map<String, Object?> observed = <String, Object?>{
    'preflightStatus': preflight.statusCode,
    'allowOrigin': allowOrigin,
    'missingExposed': missingExposed,
    'missingAllowed': missingAllowed,
  };
  final bool ok = originOk && missingExposed.isEmpty && missingAllowed.isEmpty;
  return CheckResult(
    ok
        ? Status.pass
        : (kit.backend.production ? Status.fail : Status.inconclusive),
    ok
        ? 'EXPOSED: the resumable start response exposes ${needed.join(', ')} to a browser origin and the preflight '
              '(HTTP ${preflight.statusCode}) allows the x-goog-upload-* request headers.'
        : 'MISSING: allow-origin "${allowOrigin.isEmpty ? 'none' : allowOrigin}", exposed headers lacking $missingExposed, '
              'allowed request headers lacking $missingAllowed (preflight HTTP ${preflight.statusCode}).',
    details: <String>[
      if (!ok && !kit.backend.production)
        'The emulator answers CORS differently from production; no browser is involved in this run.',
    ],
    observed: observed,
  );
}

Future<CheckResult> _retry5xx(Kit kit) async {
  final Uint8List data = Kit.bytes(256, 15);
  final storage = kit.newStorage(
    retry: const StorageRetryPolicy(operation: Duration(seconds: 30)),
  );
  try {
    await kit.put(storage.storage, 'retry.bin', data);
    storage.client.seen.clear();
    storage.client.faults = 2;
    final Stopwatch clock = Stopwatch()..start();
    final FullMetadata metadata = await storage.storage
        .ref(kit.name('retry.bin'))
        .metadata();
    final List<int?> statuses = <int?>[
      for (final Seen s in storage.client.seen) s.status,
    ];
    final Map<String, Object?> observed = <String, Object?>{
      'statuses': statuses,
      'size': metadata.size,
    };
    final bool ok =
        statuses.length == 3 &&
        statuses[0] == 503 &&
        statuses[1] == 503 &&
        statuses[2] == 200;
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'RETRIED: two simulated 503 answers (made by the kit, never sent to the backend) were retried with backoff '
                'and the third attempt was served (HTTP 200) after ${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s.'
          : 'The attempts ended with the statuses $statuses; expected 503, 503, 200.',
      details: const <String>[
        'A real 5xx of the backend cannot be provoked safely, so this one is simulated in the client.',
      ],
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

bool _matches(FullMetadata metadata, Uint8List data) =>
    metadata.size == data.length && metadata.md5Hash == Kit.md5Base64(data);

Future<CheckResult> _sdkResumable(Kit kit) async {
  final Uint8List data = Kit.bytes(1024 * 1024, 16);
  final storage = kit.newStorage();
  try {
    kit.charge(data.length);
    final String objectName = kit.name('sdk_resumable.bin');
    kit.track(objectName);
    final UploadTask task = storage.storage.ref(objectName).startUpload(data);
    final List<int> steps = <int>[];
    final StreamSubscription<UploadProgress> sub = task.progress.listen(
      (UploadProgress p) => steps.add(p.bytesTransferred),
    );
    final FullMetadata metadata = await task.result;
    await sub.cancel();
    final bool ok = _matches(metadata, data) && task.sessionUri != null;
    final Map<String, Object?> observed = <String, Object?>{
      'sessionUri': task.sessionUri != null,
      'events': steps.length,
      'matches': _matches(metadata, data),
    };
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'RESUMABLE: UploadTask sent ${data.length} bytes in a session (${steps.length} progress events); the stored size and md5 match.'
          : 'UploadTask finished with size ${metadata.size}, md5 match ${_matches(metadata, data)}, session URI '
                '${task.sessionUri != null ? 'present' : 'missing'}.',
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

/// Waits for the first event of [task] that [test] accepts.
Future<UploadProgress> _until(
  UploadTask task,
  bool Function(UploadProgress p) test,
) => task.progress.firstWhere(test);

Future<CheckResult> _sdkPauseResume(Kit kit) async {
  final Uint8List data = Kit.bytes(3 * 1024 * 1024, 17);
  final storage = kit.newStorage();
  try {
    kit.charge(data.length + 2 * chunkSize);
    final String objectName = kit.name('sdk_paused.bin');
    kit.track(objectName);
    final UploadTask task = storage.storage.ref(objectName).startUpload(data);
    await _until(task, (UploadProgress p) => p.bytesTransferred > 0);
    final Future<UploadProgress> paused = _until(
      task,
      (UploadProgress p) => p.state == UploadState.paused,
    );
    if (!task.pause()) {
      await task.result;
      return CheckResult(
        Status.inconclusive,
        'The upload finished before it could be paused; run it again.',
      );
    }
    final UploadProgress at = await paused.timeout(const Duration(seconds: 60));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final bool stayed = task.state == UploadState.paused;
    final bool resumed = task.resume();
    final FullMetadata metadata = await task.result;
    final bool ok =
        stayed &&
        resumed &&
        at.bytesTransferred < data.length &&
        _matches(metadata, data);
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'PAUSED at ${at.bytesTransferred} of ${data.length} bytes, stayed paused, resumed where the server '
                'stopped; the stored size and md5 match.'
          : 'Pause and resume ended with stayed-paused $stayed, resumed $resumed, stored match '
                '${_matches(metadata, data)}.',
      observed: <String, Object?>{
        'pausedAt': at.bytesTransferred,
        'stayed': stayed,
        'matches': _matches(metadata, data),
      },
    );
  } finally {
    storage.storage.close();
  }
}

Future<CheckResult> _sdkSessionResume(Kit kit) async {
  final Uint8List data = Kit.bytes(3 * 1024 * 1024, 18);
  final storage = kit.newStorage();
  UploadTask? first;
  try {
    kit.charge(data.length + 2 * chunkSize);
    final String objectName = kit.name('sdk_session.bin');
    kit.track(objectName);
    final Reference ref = storage.storage.ref(objectName);
    first = ref.startUpload(data);
    await _until(first, (UploadProgress p) => p.bytesTransferred > 0);
    final Future<UploadProgress> paused = _until(
      first,
      (UploadProgress p) => p.state == UploadState.paused,
    );
    if (!first.pause()) {
      await first.result;
      return CheckResult(
        Status.inconclusive,
        'The upload finished before it could be paused; run it again.',
      );
    }
    final UploadProgress at = await paused.timeout(const Duration(seconds: 60));
    final Uri? session = first.sessionUri;
    if (session == null) {
      return CheckResult(Status.fail, 'A paused upload has no session URI.');
    }
    // The app "restarts": a second task knows only the reference, the data and the session URI.
    final UploadTask second = ref.startUpload(
      data,
      existingSessionUri: session,
    );
    final FullMetadata metadata = await second.result;
    final bool ok = _matches(metadata, data);
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'RESUMED by session URI: a new task continued the upload paused at ${at.bytesTransferred} of '
                '${data.length} bytes; the stored size and md5 match.'
          : 'The task resumed by session URI stored size ${metadata.size}, md5 match $ok.',
      observed: <String, Object?>{
        'pausedAt': at.bytesTransferred,
        'matches': ok,
      },
    );
  } finally {
    if (first != null && first.state != UploadState.success) {
      first.cancel();
      try {
        await first.result;
      } on FirebaseStorageException {
        // canceled, as asked
      }
    }
    storage.storage.close();
  }
}

Future<CheckResult> _sdkDownload(Kit kit) async {
  final Uint8List data = Kit.bytes(64 * 1024, 19);
  final storage = kit.newStorage();
  try {
    await kit.put(storage.storage, 'sdk_download.bin', data);
    final Reference ref = storage.storage.ref(kit.name('sdk_download.bin'));
    final Uint8List whole = await ref.getBytes();
    final List<int> part = <int>[
      for (final List<int> chunk in await ref.openRead(100, 200).toList())
        ...chunk,
    ];
    final List<int> tail = <int>[
      for (final List<int> chunk
          in await ref.openRead(data.length - 10).toList())
        ...chunk,
    ];
    String tooLarge;
    try {
      await ref.getBytes(maxSize: 100);
      tooLarge = 'no error';
    } on FirebaseStorageException catch (e) {
      tooLarge = e.code;
    }
    final Uint8List limited = await ref.getBytes(maxSize: data.length);
    final Map<String, Object?> observed = <String, Object?>{
      'whole': _same(whole, data),
      'range': _same(part, data.sublist(100, 200)),
      'tail': _same(tail, data.sublist(data.length - 10)),
      'tooLarge': tooLarge,
      'limited': _same(limited, data),
    };
    final bool ok = observed.values.every(
      (Object? v) => v == true || v == 'download-size-exceeded',
    );
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'DOWNLOADED: getBytes returned all ${data.length} bytes, openRead(100, 200) and the open-ended tail '
                'returned the right bytes, maxSize 100 threw $tooLarge and maxSize = size returned everything.'
          : 'A download did not return the expected bytes: $observed.',
      observed: observed,
    );
  } finally {
    storage.storage.close();
  }
}

Future<CheckResult> _signedInRoundTrip(Kit kit) async {
  if (kit.userAuth == null) {
    return CheckResult(
      Status.skipped,
      'No throwaway user: pass --create-user (with $webApiKeyVariable or --api-key=).',
    );
  }
  final String bucket = kit.backend.deniedBucket ?? kit.backend.bucket;
  final bool rulesNeedUser = kit.backend.deniedBucket != null;
  final Uint8List data = Kit.bytes(8192, 20);
  final String objectName = kit.name('signed_in.bin');
  kit.charge(data.length);
  kit.track(objectName, bucket: bucket);
  final signedIn = kit.newStorage();
  final signedOut = kit.newStorage(signedIn: false);
  try {
    final Reference ref = signedIn.storage.refFromUrl(
      'gs://$bucket/$objectName',
    );
    final FullMetadata written = await ref.putBytes(
      data,
      metadata: const SettableMetadata(contentType: 'application/x-verify'),
    );
    final Uint8List read = await ref.getBytes();
    final FullMetadata metadata = await ref.metadata();
    final ListResult listed = await signedIn.storage
        .refFromUrl('gs://$bucket/${kit.prefix}')
        .list();
    await ref.delete();
    String after;
    try {
      await ref.metadata();
      after = 'still there';
    } on FirebaseStorageException catch (e) {
      after = e.code;
    }
    String withoutUser = 'not tried (the bucket does not need a user)';
    if (rulesNeedUser) {
      final Reference anonymous = signedOut.storage.refFromUrl(
        'gs://$bucket/$objectName',
      );
      try {
        await anonymous.getBytes();
        withoutUser = 'served';
      } on FirebaseStorageException catch (e) {
        withoutUser = e.code;
      }
    }
    final Map<String, Object?> observed = <String, Object?>{
      'bytes': _same(read, data),
      'md5': _matches(written, data) && metadata.md5Hash == written.md5Hash,
      'listed': listed.items.any((Reference r) => r.fullPath == objectName),
      'afterDelete': after,
      'withoutUser': withoutUser,
    };
    final bool ok =
        observed['bytes'] == true &&
        observed['md5'] == true &&
        observed['listed'] == true &&
        after == 'object-not-found' &&
        (!rulesNeedUser || withoutUser == 'unauthorized');
    return CheckResult(
      ok ? Status.pass : Status.fail,
      ok
          ? 'ROUND TRIP: as the throwaway user the SDK uploaded, read, described, listed and deleted an object in $bucket; '
                '${rulesNeedUser ? 'the same read without a user answered $withoutUser' : 'the bucket does not refuse requests without a user, so that was not tried'}.'
          : 'The round trip did not end as expected: $observed.',
      observed: observed,
    );
  } finally {
    signedIn.storage.close();
    signedOut.storage.close();
  }
}

const List<Check> checks = <Check>[
  Check('1', 'Error answer of a missing object (404 envelope)', _error404),
  Check('2', 'Error answer under rules (403 envelope)', _error403),
  Check('3', 'Range requests on a download', _range),
  Check('4', 'Download URL token', _downloadToken),
  Check('5', 'List paging and token format', _listPaging),
  Check('6', 'Multipart upload', _multipart),
  Check('7', 'Resumable upload, three chunks', _resumable),
  Check('8', 'Resumable upload, pause and resume', _pauseResume),
  Check('9', 'Resumable upload, resume by session URI', _resumeBySessionUri),
  Check('10', 'md5Hash upload integrity', _md5),
  Check('11', 'App Check header', _appCheck),
  Check('12', 'X-Firebase-GMPID header', _gmpid),
  Check('13', 'Refresh after a 401', _refresh401),
  Check('14', 'CORS headers of the resumable protocol', _cors),
  Check('15', 'Retry on a 5xx', _retry5xx),
  Check('16', 'SDK resumable upload (UploadTask)', _sdkResumable),
  Check('17', 'SDK upload, pause and resume', _sdkPauseResume),
  Check('18', 'SDK upload, resume by session URI', _sdkSessionResume),
  Check('19', 'SDK download, ranges and maxSize', _sdkDownload),
  Check('20', 'Signed-in round trip', _signedInRoundTrip),
];

// ---------------------------------------------------------------------------------------------------------------
// The command line.

const String usage =
    '''
Usage: dart run test/production/verify_production.dart --backend=production|emulator [options]

  --backend=production   Cloud Storage for Firebase; needs FIREBASE_TEST_PROJECT_ID and
                         FIREBASE_TEST_STORAGE_BUCKET (or --bucket=). Prints the plan and does nothing without --yes.
  --backend=emulator     The emulator at FIREBASE_STORAGE_EMULATOR_HOST (project demo-test).
  --yes                  Confirms a run against production.
  --bucket=NAME          The bucket to write below the run's prefix (default: the variable, or on the emulator
                         demo-test.appspot.com).
  --denied-bucket=NAME   A bucket whose rules refuse requests without a user: runs check 2 (otherwise SKIPPED).
  --api-key=KEY          The Web API key of the project (default: FIREBASE_API_KEY).
  --create-user          Signs up a throwaway user storage-verify-<run>@example.com with a random password kept in
                         memory, runs the checks as that user and deletes the user at the end, also when checks
                         fail. Needs the API key and the Email/Password provider (on the emulator also
                         FIREBASE_AUTH_EMULATOR_HOST). Without it requests carry no user.
  --only=1,2             Runs only these checks.
  --max-bytes=N          The cap on the bytes uploaded in total (default $defaultMaxBytes = 64 MiB).
  --keep                 Does not delete the objects of the run at the end.
  --list                 Lists the checks and exits.
''';

/// What a run of the kit produced.
class KitRun {
  KitRun(
    this.exitCode,
    this.results,
    this.uploadedBytes,
    this.deleted,
    this.prefix,
  );

  final int exitCode;
  final Map<String, CheckResult> results;
  final int uploadedBytes;
  final int deleted;
  final String? prefix;
}

/// Runs the kit. [environment] defaults to the environment of the process.
Future<KitRun> runKit(
  List<String> arguments, {
  StringSink? out,
  Map<String, String>? environment,
}) async {
  final StringSink sink = out ?? stdout;
  final Map<String, String> env = environment ?? Platform.environment;
  String? option(String name) {
    for (final String argument in arguments) {
      if (argument.startsWith('--$name=')) {
        return argument.substring(name.length + 3);
      }
    }
    return null;
  }

  String? setting(String name) {
    final String? value = env[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  KitRun usageError(String message) {
    sink
      ..writeln(message)
      ..writeln(usage);
    return KitRun(2, <String, CheckResult>{}, 0, 0, null);
  }

  const Set<String> flags = <String>{
    '--yes',
    '--keep',
    '--list',
    '--create-user',
  };
  const Set<String> options = <String>{
    'backend',
    'only',
    'max-bytes',
    'bucket',
    'denied-bucket',
    'api-key',
  };
  for (final String argument in arguments) {
    final bool known =
        flags.contains(argument) ||
        options.any((String name) => argument.startsWith('--$name='));
    if (!known) {
      return usageError('Unknown argument: $argument');
    }
  }
  if (arguments.contains('--list')) {
    for (final Check check in checks) {
      sink.writeln('${check.id.padRight(3)} ${check.name}');
    }
    return KitRun(0, <String, CheckResult>{}, 0, 0, null);
  }

  final String? backendName = option('backend');
  final String? emulatorHost = setting(emulatorHostVariable);
  final Backend backend;
  if (backendName == 'production') {
    if (emulatorHost != null) {
      return usageError(
        '$emulatorHostVariable is set. Unset it for --backend=production, so that it is unambiguous where the kit writes.',
      );
    }
    final String? project = setting(projectVariable);
    final String? bucket = option('bucket') ?? setting(bucketVariable);
    if (project == null || bucket == null) {
      return usageError(
        '$projectVariable and $bucketVariable (or --bucket=) name the project and the bucket to verify.',
      );
    }
    backend = Backend(
      production: true,
      projectId: project,
      bucket: bucket,
      deniedBucket: option('denied-bucket'),
      emulatorHost: null,
      appId: setting(appIdVariable) ?? '1:0:dart:verify-storage-kit',
      apiKey:
          option('api-key') ??
          setting(webApiKeyVariable) ??
          'verify-storage-kit-no-key',
    );
  } else if (backendName == 'emulator') {
    if (emulatorHost == null) {
      return usageError(
        '$emulatorHostVariable is not set: it is the host:port of the Storage emulator.',
      );
    }
    backend = Backend(
      production: false,
      projectId: 'demo-test',
      bucket: option('bucket') ?? 'demo-test.appspot.com',
      deniedBucket: option('denied-bucket'),
      emulatorHost: emulatorHost,
      appId: '1:0:dart:verify-storage-kit',
      apiKey: option('api-key') ?? setting(webApiKeyVariable) ?? 'fake-api-key',
    );
  } else {
    return usageError(
      '--backend=production or --backend=emulator is required.',
    );
  }

  final int? maxBytes = int.tryParse(option('max-bytes') ?? '$defaultMaxBytes');
  if (maxBytes == null || maxBytes < 0) {
    return usageError('--max-bytes needs a number of bytes.');
  }
  final bool createUser = arguments.contains('--create-user');
  if (createUser) {
    if (backend.production && backend.apiKey.startsWith('verify-storage-kit')) {
      return usageError(
        '--create-user needs the Web API key: $webApiKeyVariable or --api-key=.',
      );
    }
    if (!backend.production && setting(authEmulatorHostVariable) == null) {
      return usageError(
        '--create-user on the emulator needs $authEmulatorHostVariable (tool/start_auth_emulators.sh).',
      );
    }
  }

  final Set<String>? only = option('only')?.split(',').toSet();
  if (only != null) {
    final Set<String> unknown = only.difference(
      checks.map((Check c) => c.id).toSet(),
    );
    if (unknown.isNotEmpty) {
      return usageError('Unknown check ids: $unknown');
    }
  }
  final List<Check> selected = <Check>[
    for (final Check check in checks)
      if (only == null || only.contains(check.id)) check,
  ];

  final DateTime now = DateTime.now().toUtc();
  final String runId =
      'run_${now.toIso8601String().replaceAll(RegExp('[^0-9]'), '').substring(0, 14)}_${now.microsecond.toRadixString(36)}${math.Random().nextInt(1296).toRadixString(36)}';
  final String prefix = 'verify_storage_kit/$runId';
  sink
    ..writeln('Storage production verification kit')
    ..writeln('  backend:   ${backend.label} (${backend.origin})')
    ..writeln('  project:   ${backend.projectId}')
    ..writeln('  bucket:    ${backend.bucket}')
    ..writeln(
      '  denied:    ${backend.deniedBucket ?? 'none (check 2 is skipped)'}',
    )
    ..writeln(
      '  prefix:    $prefix/ (the only place written, listed and deleted)',
    )
    ..writeln(
      '  user:      ${createUser ? 'a throwaway user storage-verify-$runId@example.com is signed up with a random password and deleted at the end' : 'none (requests carry no user; checks 13 and 20 are skipped)'}',
    )
    ..writeln(
      '  cost:      at most $maxBytes bytes uploaded in total; every object is deleted at the end',
    )
    ..writeln('  checks:    ${selected.map((Check c) => c.id).join(', ')}');
  if (backend.production && !arguments.contains('--yes')) {
    sink
      ..writeln('')
      ..writeln(
        'Nothing was done. Pass --yes to run this against the real project and bucket above.',
      );
    return KitRun(2, <String, CheckResult>{}, 0, 0, prefix);
  }
  sink.writeln('');

  FirebaseUserAuth? auth;
  String? uid;
  if (createUser) {
    final FirebaseApp authApp = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: backend.apiKey,
        appId: backend.appId,
        projectId: backend.projectId,
        storageBucket: backend.bucket,
      ),
      name: 'verify-storage-auth-$runId',
    );
    auth = await FirebaseUserAuth.forApp(
      authApp,
      emulatorHost: backend.production
          ? null
          : setting(authEmulatorHostVariable),
    );
    final math.Random secure = math.Random.secure();
    const String alphabet =
        'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final String password = <String>[
      for (int i = 0; i < 32; i++) alphabet[secure.nextInt(alphabet.length)],
    ].join();
    try {
      final UserCredential created = await auth.createUserWithEmailAndPassword(
        email: 'storage-verify-$runId@example.com',
        password: password,
      );
      uid = created.user?.uid;
    } on FirebaseAuthException catch (e) {
      sink.writeln(
        'Signing up the throwaway user failed: ${e.code}. Nothing was written.',
      );
      return KitRun(2, <String, CheckResult>{}, 0, 0, prefix);
    }
  }

  final Kit kit = Kit(backend, runId, maxBytes, sink, env, auth);
  final Map<String, CheckResult> results = <String, CheckResult>{};
  int deleted = 0;
  try {
    for (final Check check in selected) {
      sink.writeln('[${check.id}] ${check.name} ...');
      CheckResult result;
      try {
        result = await check.run(kit).timeout(const Duration(minutes: 3));
      } on ByteCapExceeded catch (e) {
        result = CheckResult(
          Status.inconclusive,
          'Stopped before uploading: ${e.message} Raise --max-bytes to run this check.',
        );
      } on TimeoutException catch (e) {
        result = CheckResult(
          Status.inconclusive,
          'The check did not finish: ${e.message ?? 'timed out after ${e.duration}'}',
        );
      } on FirebaseStorageException catch (e) {
        final bool permission =
            e.code == 'unauthorized' || e.code == 'unauthenticated';
        result = CheckResult(
          permission ? Status.inconclusive : Status.fail,
          permission
              ? 'The backend refused the request: ${_describe(e)}'
              : 'Unexpected error: ${_describe(e)}',
          details: <String>[
            if (permission)
              'Check the rules of the bucket for the prefix verify_storage_kit/ and the test user.',
          ],
        );
      } on Object catch (e) {
        result = CheckResult(Status.fail, 'Unexpected error: ${_describe(e)}');
      }
      results[check.id] = result;
      sink.writeln('[${check.id}] ${result.status.label}: ${result.summary}');
      for (final String detail in result.details) {
        sink.writeln('       $detail');
      }
      sink.writeln('');
    }
  } finally {
    if (arguments.contains('--keep')) {
      sink.writeln('--keep: the objects below $prefix/ were not deleted.');
    } else {
      try {
        deleted = await kit.cleanUp();
        sink.writeln(
          'Clean-up: $deleted objects deleted below $prefix/ (every object the run could have written).',
        );
      } on Object catch (e) {
        sink
          ..writeln('Clean-up FAILED: ${_describe(e)}')
          ..writeln(
            'Delete the objects below $prefix/ in bucket ${backend.bucket} by hand (for example in the console).',
          );
      }
    }
    if (auth != null) {
      try {
        await auth.deleteCurrentUser();
        sink.writeln('The throwaway user was deleted.');
      } on Object catch (e) {
        sink.writeln(
          'Deleting the throwaway user FAILED: ${_describe(e)}. Delete the user with uid $uid by hand '
          '(Authentication > Users in the console).',
        );
      }
    }
    await kit.close();
  }

  sink
    ..writeln('')
    ..writeln(
      'Summary (${backend.label}, project ${backend.projectId}, bucket ${backend.bucket}):',
    );
  for (final Check check in selected) {
    final CheckResult result = results[check.id]!;
    sink.writeln(
      '  ${check.id.padRight(3)} ${result.status.label.padRight(12)} ${check.name}',
    );
  }
  sink.writeln(
    '  uploaded: ${kit.uploadedBytes} of at most $maxBytes bytes, deleted: $deleted',
  );
  final bool failed = results.values.any(
    (CheckResult r) => r.status == Status.fail,
  );
  return KitRun(failed ? 1 : 0, results, kit.uploadedBytes, deleted, prefix);
}

Future<void> main(List<String> arguments) async {
  final KitRun run = await runKit(arguments);
  await stdout.flush();
  exit(run.exitCode);
}
