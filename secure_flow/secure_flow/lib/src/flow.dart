import 'dart:async';

import 'package:secure_flow/src/deadline.dart';
import 'package:secure_flow/src/environment.dart';
import 'package:secure_flow/src/errors.dart';
import 'package:secure_flow/src/loopback_runner_stub.dart'
    if (dart.library.io) 'package:secure_flow/src/loopback_server.dart';
import 'package:secure_flow/src/presenter.dart';

/// What a flow is for. A presenter may use it to choose how it shows the flow, but a presenter
/// that does not know a purpose (one added later) must still present the URL of the flow.
enum SecureFlowPurpose {
  /// An OAuth 2.0 authorization code request whose redirect comes back to the loopback server.
  oauth,

  /// A reCAPTCHA check served from the loopback server.
  recaptcha,

  /// A code typed by the person into a page of the loopback server.
  codeEntry,
}

/// The host name the browser uses to reach the loopback server. The server checks that every
/// request carries exactly this name (and the port) in its `Host` header, so that a page of another
/// site whose name resolves to the loopback address (DNS rebinding) is refused.
enum SecureFlowHost {
  /// `127.0.0.1`: only 127.0.0.1 is bound. The host of OAuth loopback redirects (RFC 8252).
  loopbackIPv4('127.0.0.1'),

  /// `localhost`: 127.0.0.1 and, on the same port, ::1 are bound, so that a browser that resolves
  /// `localhost` to ::1 first still reaches this server and no other process. The host that
  /// reCAPTCHA site keys allow by default.
  localhost('localhost');

  const SecureFlowHost(this.hostName);

  /// The name in the URL and in the `Host` header.
  final String hostName;
}

/// How the answer of a flow is encoded.
enum SecureAnswerEncoding {
  /// In the query of a GET (an OAuth redirect).
  query,

  /// In an `application/x-www-form-urlencoded` POST body (a form of a page of the flow).
  form,
}

/// Which request completes a flow: its method and encoding, and its path.
final class SecureAnswer {
  /// A GET whose query carries the answer. [path] is the path of the request; null for a random
  /// one.
  const SecureAnswer.query({this.path}) : encoding = SecureAnswerEncoding.query;

  /// A form POST whose body carries the answer. [path] is the path of the request; null for a
  /// random one.
  const SecureAnswer.form({this.path}) : encoding = SecureAnswerEncoding.form;

  /// The fixed path of the answer (it starts with `/`), or null for a random path for each run.
  final String? path;

  /// Where the answer is.
  final SecureAnswerEncoding encoding;

  /// The HTTP method of the answer: GET for [SecureAnswerEncoding.query], POST for
  /// [SecureAnswerEncoding.form].
  String get method => encoding == SecureAnswerEncoding.query ? 'GET' : 'POST';
}

/// One run of a flow on the loopback server: where it listens and what the answer must carry.
final class SecureFlowSession {
  /// Made by the presenter for each run.
  const SecureFlowSession({
    required this.host,
    required this.port,
    required this.path,
    required this.state,
  });

  /// The host name of the URLs and of the `Host` header.
  final SecureFlowHost host;

  /// The port of the loopback server.
  final int port;

  /// The path of the answer (and of the page, when the flow serves one).
  final String path;

  /// The value of the `state` parameter that the answer must carry. Secret until the answer came.
  final String state;

  /// `http://<host>:<port>`.
  String get origin => 'http://${host.hostName}:$port';

  /// `<host>:<port>`, the `Host` header every request must carry.
  String get hostHeader => '${host.hostName}:$port';

  /// The address of [path]: [origin] followed by [path], or [origin] alone when [path] is `/` (the
  /// shape of an OAuth loopback redirect URI that some providers require, for example GitHub's
  /// `http://127.0.0.1`).
  String get address => path == '/' ? origin : '$origin$path';

  /// Leaves out the path and the state.
  @override
  String toString() => 'SecureFlowSession($hostHeader)';
}

/// A page the loopback server answers with. Pages follow the light or dark setting of the system.
final class SecurePage {
  /// A short page: [title] as its heading and [text] below it, both escaped.
  const SecurePage.message({
    required String this.title,
    required String this.text,
  }) : html = null,
       contentSecurityPolicy = null,
       referrerPolicy = 'no-referrer';

  /// A whole document, sent as it is with [contentSecurityPolicy] and [referrerPolicy]. The flow
  /// that makes it escapes what it puts in.
  const SecurePage.html(
    String this.html, {
    required String this.contentSecurityPolicy,
    this.referrerPolicy = 'no-referrer',
  }) : title = null,
       text = null;

  /// The heading of a message page.
  final String? title;

  /// The text of a message page.
  final String? text;

  /// The document of an HTML page.
  final String? html;

  /// The `Content-Security-Policy` of an HTML page.
  final String? contentSecurityPolicy;

  /// The `Referrer-Policy` of the page.
  final String referrerPolicy;
}

/// Thrown by [SecureFlow.parse] for an answer that is not good enough (for example an empty
/// token): the browser gets [page] with status 400, the state stays valid, and the presenter keeps
/// waiting.
final class SecureAnswerRejected implements Exception {
  /// A rejection that answers with [page].
  const SecureAnswerRejected(this.page);

  /// What the browser is told.
  final SecurePage page;

  @override
  String toString() => 'SecureAnswerRejected: ${page.title ?? 'page'}';
}

/// A browser round trip, self-contained: what to open or serve, which request answers it, how
/// that request becomes a [T], and which presenters fit it best.
///
/// [run] starts it. Without a presenter, the flow picks the first presenter of the environment
/// whose kind comes first in [presenterKinds] and that it can drive ([canDrive]). With one, the
/// flow uses it if it accepts it, and throws [SecureFlowRefused] otherwise; it never switches to
/// another presenter on its own.
///
/// With a [LoopbackPresenter] the flow binds the loopback server on [host] and [port], makes a
/// [SecureFlowSession] (a random path unless [answer] fixes one, and the [state], random unless the
/// flow fixes it), shows [start], serves [page] on a GET of the session path that carries the
/// state, and passes the parameters of the first request that matches [answer] and carries the
/// state (compared in constant time) to [parse]. One answer is taken, ever. A flow can also
/// complete without the server, with a presenter that returns the result itself
/// ([presentDirectly]).
///
/// A presenter never looks at the type of a flow, and a flow looks only at the kind of a
/// presenter and at the interfaces it implements, so third parties can write either.
abstract class SecureFlow<T> {
  /// For subclasses.
  const SecureFlow();

  /// How long [run] waits for an answer when no timeout is given: five minutes.
  static const Duration defaultTimeout = Duration(minutes: 5);

  /// What the flow is for.
  SecureFlowPurpose get purpose;

  /// The presenter kinds this flow accepts, best first.
  List<SecurePresenterKind> get presenterKinds;

  /// Whether this flow can drive [presenter] (its kind aside): by default, a [LoopbackPresenter].
  bool canDrive(SecurePresenter presenter) => presenter is LoopbackPresenter;

  /// Completes the flow with [presenter] without the loopback server, or returns null (the
  /// default) to run it on the server. [SecureFlow.run] applies the timeout and the cancel.
  Future<T>? presentDirectly(SecurePresenter presenter) => null;

  /// Runs the flow and returns its result.
  ///
  /// [presenter], when given, must be of a kind in [presenterKinds] that the flow can drive;
  /// otherwise a [SecureFlowRefused] is thrown before anything starts. Without one, the flow picks
  /// from [environment] ([SecureEnvironment.current] when null); a [SecureFlowNoPresenter] says
  /// that none fits.
  ///
  /// Throws a [SecureFlowTimeout] when no answer came within [timeout] ([defaultTimeout] when null)
  /// and a [SecureFlowCancelled] when [cancel] completes (with a value or an error) first; the
  /// loopback server is closed in both cases, as in every other. An error of [parse], or of the
  /// presenter, is rethrown as it is. The timeout and [cancel] apply until an answer is taken; the
  /// work of the parser after that (see [map]) is not cut short.
  Future<T> run({
    SecurePresenter? presenter,
    SecureEnvironment? environment,
    Duration? timeout,
    Future<void>? cancel,
  }) async {
    timeout ??= defaultTimeout;
    final SecurePresenter chosen = presenter == null
        ? choosePresenter(environment ?? SecureEnvironment.current())
        : _accepted(presenter);
    final Future<T>? direct = presentDirectly(chosen);
    if (direct != null) {
      return withDeadline(direct, timeout: timeout, cancel: cancel);
    }
    if (chosen is! LoopbackPresenter) {
      throw SecureFlowRefused(
        'A ${purpose.name} flow cannot run with this ${chosen.kind.name} presenter.',
      );
    }
    return runOnLoopback<T>(this, chosen, timeout: timeout, cancel: cancel);
  }

  /// The presenter of [environment] that fits best: the first one, in the order of
  /// [presenterKinds], that this flow can drive. Throws a [SecureFlowNoPresenter] when none does.
  SecurePresenter choosePresenter(SecureEnvironment environment) {
    final List<SecurePresenter> available = environment.presenters;
    for (final SecurePresenterKind kind in presenterKinds) {
      for (final SecurePresenter presenter in available) {
        if (presenter.kind == kind && canDrive(presenter)) {
          return presenter;
        }
      }
    }
    throw SecureFlowNoPresenter(
      'No presenter of $environment fits a ${purpose.name} flow (it takes '
      '${presenterKinds.map((SecurePresenterKind k) => k.name).join(', ')}): pass one.',
    );
  }

  SecurePresenter _accepted(SecurePresenter presenter) {
    if (!presenterKinds.contains(presenter.kind) || !canDrive(presenter)) {
      throw SecureFlowRefused(
        'A ${purpose.name} flow does not run with a ${presenter.kind.name} presenter '
        '(it takes ${presenterKinds.map((SecurePresenterKind k) => k.name).join(', ')}).',
      );
    }
    return presenter;
  }

  /// The host name the browser reaches the loopback server by.
  SecureFlowHost get host;

  /// The port of the loopback server; 0 (the default) for any free port.
  int get port => 0;

  /// Which request completes the flow.
  SecureAnswer get answer;

  /// The state the answer must carry, or null (the default) for a new random one for each run.
  String? get state => null;

  /// The URL the presenter opens for [session].
  Uri start(SecureFlowSession session);

  /// The page served on a GET of the session path whose `state` query parameter is the session's,
  /// or null (the default) when the flow serves no page. Called once for each such GET.
  SecurePage? page(SecureFlowSession session) => null;

  /// The result of the flow from the [parameters] of the answer (the `state` removed), for
  /// [session]. Throw [SecureAnswerRejected] to refuse the answer and keep waiting; any other error
  /// ends the flow (the browser gets [failedPage]) and is rethrown by the presenter as it is.
  FutureOr<T> parse(Map<String, String> parameters, SecureFlowSession session);

  /// The page of a request to another path, or of a request that comes after the answer.
  SecurePage get notFoundPage => const SecurePage.message(
    title: 'Not found',
    text: 'This address only answers a flow of the app.',
  );

  /// The page of a request with another `Host`, `Origin` or state.
  SecurePage get rejectedPage => const SecurePage.message(
    title: 'Not this request',
    text:
        'This request does not belong to the flow in progress. Return to the app and try again.',
  );

  /// The page of a taken answer.
  SecurePage get donePage => const SecurePage.message(
    title: 'Done',
    text: 'You can close this window and return to the app.',
  );

  /// The page of an answer whose [parse] failed.
  SecurePage get failedPage => const SecurePage.message(
    title: 'Something went wrong',
    text: 'The app could not use this answer. Return to the app and try again.',
  );

  /// This flow, with [convert] applied to its result before the browser gets [donePage]: work that
  /// decides whether the round trip worked (an OAuth code exchange) runs while the browser waits,
  /// and an error of [convert] gives the browser [failedPage].
  SecureFlow<R> map<R>(FutureOr<R> Function(T value) convert) =>
      _MappedFlow<T, R>(this, convert);
}

final class _MappedFlow<T, R> extends SecureFlow<R> {
  const _MappedFlow(this._flow, this._convert);

  final SecureFlow<T> _flow;
  final FutureOr<R> Function(T value) _convert;

  @override
  SecureFlowPurpose get purpose => _flow.purpose;

  @override
  List<SecurePresenterKind> get presenterKinds => _flow.presenterKinds;

  @override
  bool canDrive(SecurePresenter presenter) => _flow.canDrive(presenter);

  @override
  Future<R>? presentDirectly(SecurePresenter presenter) {
    final Future<T>? direct = _flow.presentDirectly(presenter);
    return direct?.then<R>(_convert);
  }

  @override
  SecureFlowHost get host => _flow.host;

  @override
  int get port => _flow.port;

  @override
  SecureAnswer get answer => _flow.answer;

  @override
  String? get state => _flow.state;

  @override
  Uri start(SecureFlowSession session) => _flow.start(session);

  @override
  SecurePage? page(SecureFlowSession session) => _flow.page(session);

  @override
  Future<R> parse(
    Map<String, String> parameters,
    SecureFlowSession session,
  ) async => _convert(await _flow.parse(parameters, session));

  @override
  SecurePage get notFoundPage => _flow.notFoundPage;

  @override
  SecurePage get rejectedPage => _flow.rejectedPage;

  @override
  SecurePage get donePage => _flow.donePage;

  @override
  SecurePage get failedPage => _flow.failedPage;
}
