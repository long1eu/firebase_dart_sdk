// The loopback server through a presenter, against a simulated browser: the accept rule and the
// Host of each flow, the single-use state, the timeout, cancel, and that the server is closed on
// every exit.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:secure_flow/secure_flow.dart';
import 'package:test/test.dart';

import 'browser.dart';

const String _siteKey = '6LcTestSiteKey-for_the_loopback_page_0001';

/// Runs [flow] with a presenter whose "browser" is [browser]; returns once the browser is done too.
Future<T> _run<T>(
  SecureFlow<T> flow,
  Future<void> Function(Uri url) browser, {
  Duration timeout = const Duration(seconds: 10),
  Future<void>? cancel,
}) async {
  final Completer<void> done = Completer<void>();
  done.future.ignore();
  final T result = await CallbackPresenter((Uri url) async {
    try {
      await browser(url);
      done.complete();
    } catch (e, s) {
      done.completeError(e, s);
      rethrow;
    }
  }).run(flow, timeout: timeout, cancel: cancel);
  await done.future;
  return result;
}

/// The error [future] ends with.
Future<Object> _errorOf(Future<Object?> future) => future.then<Object>(
  (Object? value) => fail('expected an error, got $value'),
  onError: (Object e) => e,
);

/// Expects that nothing of the flow answers any more at [url], on either address.
Future<void> _expectClosed(Uri url, String marker) async {
  expect(
    await answers(url, '127.0.0.1', marker),
    isFalse,
    reason: '127.0.0.1 still answers',
  );
  if (await hasIPv6()) {
    expect(
      await answers(url, '::1', marker),
      isFalse,
      reason: '::1 still answers',
    );
  }
}

/// An OAuth flow whose result is the redirect (a loopback presenter never returns tokens).
SecureFlow<OAuthRedirect> _oauth({
  String state = 'the-client-state',
  String redirectPath = '/',
}) => OAuthFlow(
  providerId: 'oidc.fake',
  authorizationUrl: (String redirectUri) => Uri.parse(redirectUri),
  state: state,
  redirectPath: redirectPath,
).map((OAuthResult result) => result as OAuthRedirect);

/// The redirect URL a provider would send the browser to.
Uri _redirect(Uri redirectUri, Map<String, String> query) =>
    redirectUri.replace(
      path: redirectUri.path.isEmpty ? '/' : null,
      queryParameters: query,
    );

/// A flow of a third party: a GET with a query on a fixed path of localhost, whose result is a
/// number.
final class _NumberFlow extends SecureFlow<int> {
  const _NumberFlow();

  @override
  SecureFlowPurpose get purpose => SecureFlowPurpose.codeEntry;

  @override
  List<SecurePresenterKind> get presenterKinds => SecurePresenterKind.values;

  @override
  SecureFlowHost get host => SecureFlowHost.localhost;

  @override
  SecureAnswer get answer => const SecureAnswer.query(path: '/number');

  @override
  Uri start(SecureFlowSession session) =>
      Uri.parse('${session.address}?state=${session.state}');

  @override
  int parse(Map<String, String> parameters, SecureFlowSession session) {
    final int? n = int.tryParse(parameters['n'] ?? '');
    if (n == null) {
      throw const SecureAnswerRejected(
        SecurePage.message(title: 'NaN', text: 'Not a number.'),
      );
    }
    if (n < 0) {
      throw StateError('negative');
    }
    return n;
  }
}

void main() {
  group('OAuthFlow on the server', () {
    test(
      'the redirect with the state is the result; the server is closed after',
      () async {
        late Uri presented;
        late Answer page;
        final OAuthRedirect redirect = await _run(_oauth(), (Uri url) async {
          presented = url;
          page = await send(
            'GET',
            _redirect(url, <String, String>{
              'code': 'c',
              'state': 'the-client-state',
            }),
          );
        });
        expect(presented.host, '127.0.0.1');
        expect(presented.path, isEmpty);
        expect(redirect.parameters, <String, String>{'code': 'c'});
        expect(redirect.redirectUri, presented.toString());
        expect(page.status, HttpStatus.ok);
        expect(page.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
        expect(page.headers.value('x-frame-options'), 'DENY');
        expect(
          page.headers.value('content-security-policy'),
          startsWith("default-src 'none'"),
        );
        expect(page.body, contains('return to the app'));
        await _expectClosed(presented, 'sign-in');
      },
    );

    test(
      'Host must be 127.0.0.1:<port>; localhost and other names get a 400',
      () async {
        final List<int> statuses = <int>[];
        await _run(_oauth(), (Uri url) async {
          final Uri good = _redirect(url, <String, String>{
            'code': 'c',
            'state': 'the-client-state',
          });
          for (final String host in <String>[
            'localhost:${url.port}',
            'evil.example',
            '127.0.0.1',
          ]) {
            statuses.add((await send('GET', good, hostHeader: host)).status);
          }
          await send('GET', good);
        });
        expect(statuses, <int>[400, 400, 400]);
      },
    );

    test(
      'other paths and methods get a 404; wrong or missing state a 400',
      () async {
        final List<int> statuses = <int>[];
        final OAuthRedirect redirect = await _run(
          _oauth(redirectPath: '/callback'),
          (Uri url) async {
            expect(url.path, '/callback');
            final Uri good = url.replace(
              queryParameters: <String, String>{
                'code': 'c',
                'state': 'the-client-state',
              },
            );
            statuses
              ..add((await send('GET', good.replace(path: '/'))).status)
              ..add(
                (await send('GET', good.replace(path: '/favicon.ico'))).status,
              )
              ..add((await send('POST', good)).status)
              ..add(
                (await send(
                  'GET',
                  good.replace(
                    queryParameters: <String, String>{
                      'code': 'c',
                      'state': 'x',
                    },
                  ),
                )).status,
              )
              ..add(
                (await send(
                  'GET',
                  good.replace(queryParameters: <String, String>{'code': 'c'}),
                )).status,
              )
              ..add(
                (await send(
                  'GET',
                  Uri.parse('${url.replace(query: '')}?code=c&state=%ff'),
                )).status,
              );
            await send('GET', good);
          },
        );
        expect(statuses, <int>[404, 404, 404, 400, 400, 400]);
        expect(redirect.parameters['code'], 'c');
      },
    );

    test(
      'a state is good once: a redirect while the first is taken gets a 404',
      () async {
        final Completer<void> release = Completer<void>();
        late Answer second;
        final OAuthRedirect redirect = await _run(
          _oauth().map((OAuthRedirect r) async {
            await release.future;
            return r;
          }),
          (Uri url) async {
            final Uri good = _redirect(url, <String, String>{
              'code': 'c',
              'state': 'the-client-state',
            });
            final Future<Answer> first = send('GET', good);
            await Future<void>.delayed(const Duration(milliseconds: 100));
            second = await send(
              'GET',
              good.replace(
                queryParameters: <String, String>{
                  'code': 'other',
                  'state': 'the-client-state',
                },
              ),
            );
            release.complete();
            expect((await first).status, HttpStatus.ok);
          },
        );
        expect(second.status, HttpStatus.notFound);
        expect(second.body, contains('only receives the sign-in redirect'));
        expect(redirect.parameters['code'], 'c');
      },
    );

    test(
      'map runs before the browser gets the page; its error is rethrown with a 400 page',
      () async {
        late Answer page;
        final Object error = await _errorOf(
          _run(
            _oauth().map<String>(
              (OAuthRedirect r) =>
                  throw const FormatException('exchange failed'),
            ),
            (Uri url) async {
              page = await send(
                'GET',
                _redirect(url, <String, String>{
                  'code': 'c',
                  'state': 'the-client-state',
                }),
              );
            },
          ),
        );
        expect(error, isA<FormatException>());
        expect(page.status, HttpStatus.badRequest);
        expect(page.body, contains('The sign-in did not complete'));
      },
    );

    test('a web view presenter is refused before anything is bound', () async {
      bool shown = false;
      final Object error = await _errorOf(
        CallbackPresenter(
          (_) => shown = true,
          kind: SecurePresenterKind.embeddedWebView,
        ).run(_oauth()),
      );
      expect(error, isA<SecureFlowRefused>());
      expect(shown, isFalse);
      // A flow that ranks web views runs in one.
      final String token = await CallbackPresenter(
        (Uri url) async {
          await postForm(url, <String, String>{
            'state': url.queryParameters['state']!,
            'token': 't',
          });
        },
        kind: SecurePresenterKind.embeddedWebView,
      ).run(RecaptchaFlow(siteKey: _siteKey));
      expect(token, 't');
    });
  });

  group('RecaptchaFlow on the server', () {
    test(
      'page then token; localhost on 127.0.0.1 and ::1, same port; closed after',
      () async {
        final bool ipv6 = await hasIPv6();
        late Uri presented;
        final List<int> statuses = <int>[];
        final String token = await _run(RecaptchaFlow(siteKey: _siteKey), (
          Uri url,
        ) async {
          presented = url;
          statuses.add((await send('GET', url, address: '127.0.0.1')).status);
          if (ipv6) {
            statuses.add((await send('GET', url, address: '::1')).status);
          }
          final Answer done = await postForm(url, <String, String>{
            'state': url.queryParameters['state']!,
            'token': 'the-token',
          }, origin: 'http://localhost:${url.port}');
          expect(done.status, HttpStatus.ok);
          expect(done.body, isNot(contains('the-token')));
        });
        expect(token, 'the-token');
        expect(presented.host, 'localhost');
        expect(presented.pathSegments.single, hasLength(43));
        expect(presented.queryParameters['state'], hasLength(43));
        expect(statuses, <int>[200, if (ipv6) 200]);
        await _expectClosed(presented, 'reCAPTCHA');
      },
    );

    test(
      'Host 127.0.0.1 or another name, or another Origin, gets a 400',
      () async {
        final List<int> statuses = <int>[];
        await _run(RecaptchaFlow(siteKey: _siteKey), (Uri url) async {
          final Map<String, String> answer = <String, String>{
            'state': url.queryParameters['state']!,
            'token': 't',
          };
          statuses
            ..add(
              (await send(
                'GET',
                url,
                hostHeader: '127.0.0.1:${url.port}',
              )).status,
            )
            ..add(
              (await send(
                'GET',
                url,
                hostHeader: 'evil.example:${url.port}',
              )).status,
            )
            ..add(
              (await postForm(url, answer, hostHeader: 'evil.example')).status,
            )
            ..add(
              (await postForm(
                url,
                answer,
                origin: 'http://evil.example',
              )).status,
            )
            ..add(
              (await postForm(
                url,
                answer,
                origin: 'http://127.0.0.1:${url.port}',
              )).status,
            );
          await postForm(url, answer);
        });
        expect(statuses, <int>[400, 400, 400, 400, 400]);
      },
    );

    test(
      'the page needs the state; a wrong state does not end the wait',
      () async {
        final List<int> statuses = <int>[];
        final String token = await _run(RecaptchaFlow(siteKey: _siteKey), (
          Uri url,
        ) async {
          statuses
            ..add(
              (await send(
                'GET',
                url.replace(queryParameters: <String, String>{'state': 'x'}),
              )).status,
            )
            ..add((await send('GET', url.replace(query: ''))).status)
            ..add(
              (await postForm(url, <String, String>{
                'state': 'x' * 43,
                'token': 'forged',
              })).status,
            )
            ..add(
              (await postForm(url, <String, String>{'token': 'forged'})).status,
            )
            ..add((await send('PUT', url)).status);
          await postForm(url, <String, String>{
            'state': url.queryParameters['state']!,
            'token': 'real',
          });
        });
        expect(token, 'real');
        expect(statuses, <int>[400, 400, 400, 400, 404]);
      },
    );

    test(
      'of two answers at once, one wins and the other does not get a 200',
      () async {
        final List<Object> outcomes = <Object>[];
        final String token = await _run(RecaptchaFlow(siteKey: _siteKey), (
          Uri url,
        ) async {
          Future<Object> attempt(String token) =>
              postForm(url, <String, String>{
                'state': url.queryParameters['state']!,
                'token': token,
              }).then<Object>(
                (Answer a) => a.status,
                onError: (Object e) => 'closed',
              );
          outcomes.addAll(
            await Future.wait(<Future<Object>>[attempt('one'), attempt('two')]),
          );
        });
        expect(<String>['one', 'two'], contains(token));
        expect(outcomes.where((Object o) => o == 200), hasLength(1));
        expect(
          outcomes.where((Object o) => o != 200),
          everyElement(anyOf(404, 'closed')),
        );
      },
    );

    test(
      'two form answers whose bodies come late: the second gets a 404 once the first is taken',
      () async {
        final Completer<void> release = Completer<void>();
        late String second;
        final String token = await _run(
          RecaptchaFlow(siteKey: _siteKey).map((String token) async {
            await release.future;
            return token;
          }),
          (Uri url) async {
            final String state = url.queryParameters['state']!;
            // Both requests are dispatched before either body arrives.
            final _RawPost a = await _RawPost.open(
              url,
              'state=$state&token=one',
            );
            final _RawPost b = await _RawPost.open(
              url,
              'state=$state&token=two',
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
            a.sendBody();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            b.sendBody();
            second = await b.response();
            release.complete();
            expect(await a.response(), startsWith('HTTP/1.1 200'));
          },
        );
        expect(token, 'one');
        expect(second, startsWith('HTTP/1.1 404'));
      },
    );

    test('a rejected answer keeps the state for a retry', () async {
      final List<Answer> answers = <Answer>[];
      final String token = await _run(RecaptchaFlow(siteKey: _siteKey), (
        Uri url,
      ) async {
        final String state = url.queryParameters['state']!;
        answers
          ..add(await postForm(url, <String, String>{'state': state}))
          ..add(
            await postForm(url, <String, String>{'state': state, 'token': ''}),
          );
        await postForm(url, <String, String>{
          'state': state,
          'token': 'second-try',
        });
      });
      expect(token, 'second-try');
      expect(answers.map((Answer a) => a.status), <int>[400, 400]);
      expect(answers.first.body, contains('returned no token'));
    });

    test('not a form, too large, or not decodable: refused', () async {
      final List<int> statuses = <int>[];
      await _run(RecaptchaFlow(siteKey: _siteKey), (Uri url) async {
        final String state = url.queryParameters['state']!;
        statuses
          ..add(
            (await postForm(url, <String, String>{
              'state': state,
              'token': 't',
            }, contentType: 'text/plain')).status,
          )
          ..add(
            (await postForm(
              url,
              const <String, String>{},
              rawBody: 'state=$state&token=${'a' * (70 * 1024)}',
            )).status,
          )
          ..add(
            (await postForm(
              url,
              const <String, String>{},
              rawBody: 'state=$state&token=%FF%',
            )).status,
          );
        await postForm(url, <String, String>{'state': state, 'token': 't'});
      });
      expect(statuses, <int>[400, 413, 400]);
    });
  });

  group('CodeEntryFlow on the server', () {
    test('the form, then the code; Host must be 127.0.0.1', () async {
      final List<int> statuses = <int>[];
      final String code = await _run(const CodeEntryFlow(prompt: 'The code'), (
        Uri url,
      ) async {
        expect(url.host, '127.0.0.1');
        final Answer page = await send('GET', url);
        expect(page.status, HttpStatus.ok);
        expect(page.body, contains('The code'));
        final String state = url.queryParameters['state']!;
        statuses
          ..add(
            (await send(
              'GET',
              url,
              hostHeader: 'localhost:${url.port}',
            )).status,
          )
          ..add(
            (await postForm(url, <String, String>{
              'state': state,
              'code': ' ',
            })).status,
          );
        expect(
          (await postForm(url, <String, String>{
            'state': state,
            'code': '123456',
          })).status,
          200,
        );
      });
      expect(code, '123456');
      expect(statuses, <int>[400, 400]);
    });
  });

  group('a flow of a third party', () {
    test('runs with its own accept rule, host and parser', () async {
      final List<int> statuses = <int>[];
      final int n = await _run(const _NumberFlow(), (Uri url) async {
        expect(url.host, 'localhost');
        expect(url.path, '/number');
        final String state = url.queryParameters['state']!;
        statuses
          ..add(
            (await send(
              'GET',
              url.replace(
                queryParameters: <String, String>{'state': state, 'n': 'x'},
              ),
            )).status,
          )
          ..add(
            (await send(
              'GET',
              url.replace(
                queryParameters: <String, String>{'state': state, 'n': '7'},
              ),
            )).status,
          );
      });
      expect(n, 7);
      expect(statuses, <int>[400, 200]);
    });

    test(
      'an error of its parser ends the run as it is and closes the server',
      () async {
        late Uri presented;
        final Object error = await _errorOf(
          _run(const _NumberFlow(), (Uri url) async {
            presented = url;
            final String state = url.queryParameters['state']!;
            await send(
              'GET',
              url.replace(
                queryParameters: <String, String>{'state': state, 'n': '-1'},
              ),
            );
          }),
        );
        expect(error, isA<StateError>());
        await _expectClosed(presented, 'answers a flow');
      },
    );
  });

  group('the end of a run', () {
    test(
      'timeout: a typed error without secrets, and the server is closed',
      () async {
        late Uri presented;
        final Object error = await _errorOf(
          _run(
            RecaptchaFlow(siteKey: _siteKey),
            (Uri url) async {
              presented = url;
              await send('GET', url);
            },
            timeout: const Duration(milliseconds: 300),
          ),
        );
        expect(
          error,
          isA<SecureFlowTimeout>()
              .having(
                (SecureFlowTimeout e) => e.timeout,
                'timeout',
                const Duration(milliseconds: 300),
              )
              .having((SecureFlowTimeout e) => e.hint, 'hint', isNull),
        );
        expect(
          error.toString(),
          allOf(
            isNot(contains(presented.queryParameters['state']!)),
            isNot(contains(presented.path)),
            isNot(contains(_siteKey)),
          ),
        );
        await _expectClosed(presented, 'reCAPTCHA');
      },
    );

    test(
      'a timeout while an answer is parsed waits for it: success still wins',
      () async {
        final Completer<void> release = Completer<void>();
        final Future<String> result = _run(
          RecaptchaFlow(siteKey: _siteKey).map((String token) async {
            await release.future;
            return token;
          }),
          (Uri url) async {
            await postForm(url, <String, String>{
              'state': url.queryParameters['state']!,
              'token': 't',
            });
          },
          timeout: const Duration(milliseconds: 200),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        release.complete();
        expect(await result, 't');
      },
    );

    test(
      'a timeout while an answer is parsed: a rejection of it ends the run',
      () async {
        final Completer<void> release = Completer<void>();
        final Future<String> result =
            CallbackPresenter((Uri url) async {
              await postForm(url, <String, String>{
                'state': url.queryParameters['state']!,
                'token': 't',
              });
            }).run(
              RecaptchaFlow(siteKey: _siteKey).map<String>((
                String token,
              ) async {
                await release.future;
                throw const SecureAnswerRejected(
                  SecurePage.message(title: 'No', text: 'No.'),
                );
              }),
              timeout: const Duration(milliseconds: 200),
            );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        release.complete();
        expect(await _errorOf(result), isA<SecureFlowTimeout>());
      },
    );

    test('cancel: a typed error, and the server is closed', () async {
      final Completer<void> cancel = Completer<void>();
      late Uri presented;
      final Object error = await _errorOf(
        _run(RecaptchaFlow(siteKey: _siteKey), (Uri url) async {
          presented = url;
          expect((await send('GET', url)).status, 200);
          cancel.complete();
        }, cancel: cancel.future),
      );
      expect(error, isA<SecureFlowCancelled>());
      await _expectClosed(presented, 'reCAPTCHA');
    });

    test('cancel with an error cancels too', () async {
      final Completer<void> cancel = Completer<void>();
      final Future<String> result = CallbackPresenter((_) {
        cancel.completeError(StateError('stop'));
      }).run(RecaptchaFlow(siteKey: _siteKey), cancel: cancel.future);
      expect(await _errorOf(result), isA<SecureFlowCancelled>());
    });

    test(
      'a show that throws ends the run with its error and closes the server',
      () async {
        late Uri presented;
        final Object error = await _errorOf(
          CallbackPresenter((Uri url) {
            presented = url;
            throw StateError('no browser');
          }).run(RecaptchaFlow(siteKey: _siteKey)),
        );
        expect(error, isA<StateError>());
        await _expectClosed(presented, 'reCAPTCHA');
      },
    );

    test('a fixed port whose ::1 is taken fails for a localhost flow', () async {
      if (!await hasIPv6()) {
        // Without an IPv6 loopback only 127.0.0.1 can be bound: the flow binds that alone.
        expect(await hasIPv6(), isFalse);
        return;
      }
      final ServerSocket other = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        0,
        v6Only: true,
      );
      addTearDown(other.close);
      final Object error = await _errorOf(
        const SystemBrowserPresenter(
          open: _never,
        ).run(_FixedPortFlow(other.port)),
      );
      expect(error, isA<SocketException>());
      // 127.0.0.1 of that port was released again.
      final ServerSocket ipv4 = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        other.port,
      );
      await ipv4.close();
    });
  });
}

Future<void> _never(Uri url) => fail('nothing should be shown');

/// A localhost flow on a fixed port.
final class _FixedPortFlow extends SecureFlow<String> {
  const _FixedPortFlow(this._port);

  final int _port;

  @override
  SecureFlowPurpose get purpose => SecureFlowPurpose.codeEntry;

  @override
  List<SecurePresenterKind> get presenterKinds => SecurePresenterKind.values;

  @override
  SecureFlowHost get host => SecureFlowHost.localhost;

  @override
  int get port => _port;

  @override
  SecureAnswer get answer => const SecureAnswer.form();

  @override
  Uri start(SecureFlowSession session) => Uri.parse(session.address);

  @override
  String parse(Map<String, String> parameters, SecureFlowSession session) => '';
}

/// A form POST over a raw socket whose body is sent later, to hold a request between its headers
/// and its body.
final class _RawPost {
  _RawPost._(this._socket, this._body);

  final Socket _socket;
  final String _body;

  static Future<_RawPost> open(Uri url, String body) async {
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      url.port,
    );
    socket.write(
      'POST ${url.path} HTTP/1.1\r\n'
      'Host: ${url.host}:${url.port}\r\n'
      'Content-Type: application/x-www-form-urlencoded\r\n'
      'Content-Length: ${body.length}\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    return _RawPost._(socket, body);
  }

  void sendBody() => _socket.write(_body);

  Future<String> response() async {
    await _socket.flush();
    final String text = await utf8.decoder.bind(_socket).join();
    await _socket.close();
    return text;
  }
}
