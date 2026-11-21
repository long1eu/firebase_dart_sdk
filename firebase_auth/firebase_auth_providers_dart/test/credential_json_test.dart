// The JSON of the credentials: the shape of toJSON of the JS SDK (as JSON.stringify writes it), and
// fromJSON / OAuthProvider.credentialFromJSON reading it back.
//
// The fixtures are what the JS SDK writes, derived from its sources
// (packages/auth/src/core/credentials/email.ts, oauth.ts and phone.ts toJSON): JSON.stringify drops
// the keys whose value is undefined and keeps the null ones (EmailAuthCredential._tenantId and
// OAuthCredential.pendingToken default to null); phone.ts writes only the values that are set and
// not empty.

import 'dart:convert';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:test/test.dart';

import 'harness.dart';

const String _link =
    'https://example.firebaseapp.com/__/auth/action?apiKey=key&mode=signIn'
    '&oobCode=the-code&continueUrl=https%3A%2F%2Fexample.com&lang=en';

/// [json] after a trip through JSON text.
Map<String, Object?> _stringified(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('EmailAuthCredential', () {
    test('email and password: the JSON of the JS SDK, and back', () {
      final EmailAuthCredential credential = EmailAuthProvider.credential(
        email: 'ada@example.com',
        password: 'correct horse',
      );

      final Map<String, Object?> json = credential.toJson();

      expect(
        jsonEncode(json),
        '{"email":"ada@example.com","password":"correct horse","signInMethod":"password",'
        '"tenantId":null}',
      );
      for (final Object input in <Object>[json, jsonEncode(json)]) {
        final EmailAuthCredential read = EmailAuthCredential.fromJson(input)!;
        expect(read.providerId, 'password');
        expect(read.signInMethod, 'password');
        expect(read.email, 'ada@example.com');
        expect(read.password, 'correct horse');
        expect(read.emailLink, isNull);
        expect(read.toJson(), json);
      }
    });

    test('email link: the code of the link in password, as in the JS SDK', () {
      final EmailAuthCredential credential =
          EmailAuthProvider.credentialWithLink(
            email: 'ada@example.com',
            emailLink: _link,
          );

      final Map<String, Object?> json = credential.toJson();

      expect(
        jsonEncode(json),
        '{"email":"ada@example.com","password":"the-code","signInMethod":"emailLink",'
        '"tenantId":null}',
      );
      final EmailAuthCredential read = EmailAuthCredential.fromJson(
        jsonEncode(json),
      )!;
      expect(read.signInMethod, 'emailLink');
      expect(read.email, 'ada@example.com');
      expect(read.password, isNull);
      expect(ActionCodeURL.parseLink(read.emailLink!)!.code, 'the-code');
      expect(read.toJson(), json);
    });

    test(
      'email link of a tenant: the tenant and a code that needs escaping survive',
      () {
        final EmailAuthCredential
        credential = EmailAuthProvider.credentialWithLink(
          email: 'ada@example.com',
          emailLink:
              'https://x.test/?apiKey=k&mode=signIn&oobCode=a%26b%20c&tenantId=tenant-1',
        );

        final Map<String, Object?> json = credential.toJson();

        expect(json, <String, Object?>{
          'email': 'ada@example.com',
          'password': 'a&b c',
          'signInMethod': 'emailLink',
          'tenantId': 'tenant-1',
        });
        final EmailAuthCredential read = EmailAuthCredential.fromJson(json)!;
        final ActionCodeURL url = ActionCodeURL.parseLink(read.emailLink!)!;
        expect(url.code, 'a&b c');
        expect(url.tenantId, 'tenant-1');
        expect(read.toJson(), json);
      },
    );

    test('toJson of a link that is not an action link throws', () {
      final EmailAuthCredential credential =
          EmailAuthProvider.credentialWithLink(
            email: 'ada@example.com',
            emailLink: 'https://example.com/not-a-link',
          );

      expect(credential.toJson, throwsArgumentError);
    });

    test('fromJson returns null for JSON that is not an email credential', () {
      const Map<String, Object?> valid = <String, Object?>{
        'email': 'ada@example.com',
        'password': 'pw',
        'signInMethod': 'password',
      };
      final List<Object> inputs = <Object>[
        <String, Object?>{...valid, 'signInMethod': 'google.com'},
        <String, Object?>{...valid}..remove('signInMethod'),
        <String, Object?>{...valid}..remove('email'),
        <String, Object?>{...valid}..remove('password'),
        <String, Object?>{...valid, 'email': ''},
        <String, Object?>{...valid, 'password': ''},
        <String, Object?>{...valid, 'password': 42},
        <Object?>[valid],
        42,
        '"a string"',
        '[]',
        'null',
      ];
      for (final Object input in inputs) {
        expect(EmailAuthCredential.fromJson(input), isNull, reason: '$input');
      }
    });

    test('fromJson throws a FormatException for text that is not JSON', () {
      expect(
        () => EmailAuthCredential.fromJson('{email:'),
        throwsFormatException,
      );
    });
  });

  group('OAuthCredential', () {
    final Map<String, (OAuthCredential, String)>
    cases = <String, (OAuthCredential, String)>{
      'ID token': (
        GoogleAuthProvider.credential(idToken: 'id-token'),
        '{"idToken":"id-token","pendingToken":null,"providerId":"google.com","signInMethod":"google.com"}',
      ),
      'access token and secret': (
        TwitterAuthProvider.credential(accessToken: 'access', secret: 'secret'),
        '{"accessToken":"access","secret":"secret","pendingToken":null,"providerId":"twitter.com",'
            '"signInMethod":"twitter.com"}',
      ),
      'ID token and raw nonce': (
        AppleAuthProvider.credentialWithIDToken(
          'id-token',
          'raw-nonce',
          const AppleFullPersonName(givenName: 'Ada'),
        ),
        '{"idToken":"id-token","nonce":"raw-nonce","pendingToken":null,"providerId":"apple.com",'
            '"signInMethod":"apple.com"}',
      ),
      'every token of an OIDC provider': (
        OAuthProvider(
          'oidc.my-idp',
        ).credential(idToken: 'id', accessToken: 'access', rawNonce: 'n'),
        '{"idToken":"id","accessToken":"access","nonce":"n","pendingToken":null,"providerId":"oidc.my-idp",'
            '"signInMethod":"oidc.my-idp"}',
      ),
    };

    cases.forEach((String name, (OAuthCredential, String) testCase) {
      final (OAuthCredential credential, String fixture) = testCase;

      test('$name: the JSON of the JS SDK, and back', () {
        final Map<String, Object?> json = credential.toJson();

        expect(jsonEncode(json), fixture);
        for (final OAuthCredential read in <OAuthCredential>[
          OAuthCredential.fromJson(fixture)!,
          OAuthCredential.fromJson(_stringified(json))!,
          OAuthProvider.credentialFromJson(fixture),
        ]) {
          expect(read.providerId, credential.providerId);
          expect(read.signInMethod, credential.signInMethod);
          expect(read.idToken, credential.idToken);
          expect(read.accessToken, credential.accessToken);
          expect(read.secret, credential.secret);
          expect(read.rawNonce, credential.rawNonce);
          expect(read.pendingToken, isNull);
          expect(read.appleFullPersonName, isNull);
          expect(read.toJson(), json);
        }
      });
    });

    test(
      'a pending token is kept, and credentialFromJson drops the nonce with it as JS does',
      () {
        const String fixture =
            '{"nonce":"n","pendingToken":"pending","providerId":"oidc.x","signInMethod":"oidc.x","idToken":"id"}';

        expect(OAuthCredential.fromJson(fixture)!.pendingToken, 'pending');
        expect(OAuthCredential.fromJson(fixture)!.rawNonce, 'n');
        final OAuthCredential usable = OAuthProvider.credentialFromJson(
          fixture,
        );
        expect(usable.pendingToken, 'pending');
        expect(usable.rawNonce, isNull);
        expect(usable.toJson(), <String, Object?>{
          'idToken': 'id',
          'pendingToken': 'pending',
          'providerId': 'oidc.x',
          'signInMethod': 'oidc.x',
        });
      },
    );

    test(
      'fromJson needs no token and reads empty tokens as none, as JS does',
      () {
        final OAuthCredential read = OAuthCredential.fromJson(<String, Object?>{
          'providerId': 'google.com',
          'signInMethod': 'google.com',
          'idToken': '',
          'accessToken': '',
          'pendingToken': '',
        })!;

        expect(read.idToken, isNull);
        expect(read.accessToken, isNull);
        expect(read.pendingToken, isNull);
      },
    );

    test('fromJson returns null for JSON that is not a credential', () {
      const Map<String, Object?> valid = <String, Object?>{
        'idToken': 'id',
        'providerId': 'google.com',
        'signInMethod': 'google.com',
      };
      final List<Object> inputs = <Object>[
        <String, Object?>{...valid}..remove('providerId'),
        <String, Object?>{...valid, 'providerId': ''},
        <String, Object?>{...valid, 'providerId': 7},
        <String, Object?>{...valid}..remove('signInMethod'),
        <String, Object?>{...valid, 'idToken': 7},
        <String, Object?>{...valid, 'nonce': true},
        <Object?>[valid],
        42,
        '"a string"',
        'null',
      ];
      for (final Object input in inputs) {
        expect(OAuthCredential.fromJson(input), isNull, reason: '$input');
      }
    });

    test(
      'fromJson and credentialFromJson throw a FormatException for text that is not JSON',
      () {
        expect(
          () => OAuthCredential.fromJson('{"providerId":'),
          throwsFormatException,
        );
        expect(
          () => OAuthProvider.credentialFromJson('nope'),
          throwsFormatException,
        );
      },
    );

    test(
      'credentialFromJson throws an ArgumentError without a provider or a token',
      () {
        final List<Object> inputs = <Object>[
          <String, Object?>{'idToken': 'id', 'signInMethod': 'google.com'},
          <String, Object?>{
            'providerId': 'google.com',
            'signInMethod': 'google.com',
          },
          <String, Object?>{
            'providerId': 'oidc.x',
            'signInMethod': 'oidc.x',
            'pendingToken': 'p',
          },
          <String, Object?>{
            'providerId': 'twitter.com',
            'signInMethod': 'twitter.com',
            'secret': 's',
          },
          '[]',
          42,
        ];
        for (final Object input in inputs) {
          expect(
            () => OAuthProvider.credentialFromJson(input),
            throwsArgumentError,
            reason: '$input',
          );
        }
      },
    );

    test('toString leaves out the tokens of a credential read from JSON', () {
      final OAuthCredential read = OAuthCredential.fromJson(
        '{"idToken":"id-secret","accessToken":"access-secret","secret":"s-secret","nonce":"n-secret",'
        '"pendingToken":"p-secret","providerId":"oidc.x","signInMethod":"oidc.x"}',
      )!;
      final EmailAuthCredential email = EmailAuthCredential.fromJson(
        '{"email":"ada@example.com","password":"pw-secret","signInMethod":"password"}',
      )!;

      expect('$read $email', isNot(contains('secret')));
    });
  });
  group('PhoneAuthCredential', () {
    test('verification id and code: the JSON of the JS SDK, and back', () {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: 'session-1',
        verificationCode: '123456',
      );

      final Map<String, Object?> json = credential.toJson();

      expect(
        jsonEncode(json),
        '{"providerId":"phone","verificationCode":"123456","verificationId":"session-1"}',
      );
      for (final Object input in <Object>[json, jsonEncode(json)]) {
        final PhoneAuthCredential read = PhoneAuthCredential.fromJson(input)!;
        expect(read.providerId, 'phone');
        expect(read.signInMethod, 'phone');
        expect(read.verificationId, 'session-1');
        expect(read.verificationCode, '123456');
        expect(read.temporaryProof, isNull);
        expect(read.phoneNumber, isNull);
        expect(read.toJson(), json);
      }
    });

    test(
      'temporary proof and phone number: the JSON of the JS SDK, and back',
      () {
        const String js =
            '{"providerId":"phone","phoneNumber":"+15555550100","temporaryProof":"proof-1"}';

        final PhoneAuthCredential read = PhoneAuthCredential.fromJson(js)!;

        expect(read.temporaryProof, 'proof-1');
        expect(read.phoneNumber, '+15555550100');
        expect(read.verificationId, isNull);
        expect(read.verificationCode, isNull);
        expect(jsonEncode(read.toJson()), js);
        expect(_stringified(read.toJson()), read.toJson());
      },
    );

    test('empty values are left out of toJson and read back as missing', () {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: 'session-1',
        verificationCode: '',
      );

      expect(credential.toJson(), <String, Object?>{
        'providerId': 'phone',
        'verificationId': 'session-1',
      });
      final PhoneAuthCredential read = PhoneAuthCredential.fromJson(
        '{"verificationId":"session-1","verificationCode":"","phoneNumber":""}',
      )!;
      expect(read.verificationCode, isNull);
      expect(read.phoneNumber, isNull);
    });

    test('fromJson does not look at providerId, as in the JS SDK', () {
      final PhoneAuthCredential read = PhoneAuthCredential.fromJson(
        '{"providerId":"password","verificationId":"session-1","verificationCode":"1"}',
      )!;

      expect(read.providerId, 'phone');
      expect(read.verificationId, 'session-1');
    });

    test('fromJson returns null for JSON that is not a phone credential', () {
      final List<Object> inputs = <Object>[
        <String, Object?>{},
        <String, Object?>{'providerId': 'phone'},
        <String, Object?>{
          'verificationId': '',
          'verificationCode': '',
          'phoneNumber': '',
          'temporaryProof': '',
        },
        <String, Object?>{'verificationId': 1, 'verificationCode': '1'},
        <String, Object?>{'temporaryProof': 'p', 'phoneNumber': true},
        '[]',
        '"phone"',
        '1',
        <Object?>['verificationId'],
      ];
      for (final Object input in inputs) {
        expect(PhoneAuthCredential.fromJson(input), isNull, reason: '$input');
      }
    });

    test('fromJson throws a FormatException for text that is not JSON', () {
      expect(
        () => PhoneAuthCredential.fromJson('{verificationId:'),
        throwsFormatException,
      );
    });

    test(
      'the FormatException keeps neither the text nor the decoder\'s message',
      () {
        const String text = '{"verificationCode":"123456"';
        try {
          PhoneAuthCredential.fromJson(text);
          fail('expected a FormatException');
        } on FormatException catch (e) {
          expect(e.source, isNull);
          expect(e.message, startsWith('The credential is not valid JSON'));
          expect('$e', isNot(contains('123456')));
        }
      },
    );

    test('toString leaves out the code, the proof and the number', () {
      final PhoneAuthCredential code = PhoneAuthCredential.fromJson(
        '{"verificationId":"id-secret","verificationCode":"code-secret"}',
      )!;
      final PhoneAuthCredential proof = PhoneAuthCredential.fromJson(
        '{"temporaryProof":"proof-secret","phoneNumber":"+15555550100"}',
      )!;

      expect('$code $proof', isNot(contains('secret')));
      expect('$proof', isNot(contains('5555550100')));
    });
  });
  group('a credential read from the JSON of the JS SDK signs in', () {
    late FakeBackend backend;
    late FirebaseUserAuth auth;

    setUp(() {
      backend = FakeBackend();
      auth = backend.create();
    });

    tearDown(() => auth.dispose());

    test('an email link sends the code', () async {
      backend.on('accounts:signInWithEmailLink', (Map<String, Object?> body) {
        backend.accounts['u'] = <String, Object?>{'email': body['email']};
        return jsonResponse(backend.tokensFor('u', email: 'ada@example.com'));
      });

      await auth.signInWithCredential(
        EmailAuthCredential.fromJson(
          '{"email":"ada@example.com","password":"the-code","signInMethod":"emailLink","tenantId":null}',
        )!,
      );

      expect(
        backend.bodiesOf('accounts:signInWithEmailLink').single,
        <String, Object?>{'email': 'ada@example.com', 'oobCode': 'the-code'},
      );
    });

    test('a Twitter credential sends the token and its secret', () async {
      backend.on('accounts:signInWithIdp', (Map<String, Object?> body) {
        backend.accounts['u'] = <String, Object?>{};
        return jsonResponse(<String, Object?>{
          'providerId': 'twitter.com',
          ...backend.tokensFor('u', provider: 'twitter.com'),
        });
      });

      await auth.signInWithCredential(
        OAuthProvider.credentialFromJson(
          '{"accessToken":"access","secret":"secret","pendingToken":null,"providerId":"twitter.com",'
          '"signInMethod":"twitter.com"}',
        ),
      );

      final String postBody =
          backend.bodiesOf('accounts:signInWithIdp').single['postBody']!
              as String;
      expect(Uri.splitQueryString(postBody), <String, String>{
        'access_token': 'access',
        'oauth_token_secret': 'secret',
        'providerId': 'twitter.com',
      });
    });

    test('a phone credential sends the verification id and the code', () async {
      backend.on('accounts:signInWithPhoneNumber', (Map<String, Object?> body) {
        backend.accounts['u'] = <String, Object?>{
          'phoneNumber': '+15555550100',
        };
        return jsonResponse(backend.tokensFor('u', provider: 'phone'));
      });

      await auth.signInWithCredential(
        PhoneAuthCredential.fromJson(
          '{"providerId":"phone","verificationCode":"123456",'
          '"verificationId":"session-1"}',
        )!,
      );

      expect(
        backend.bodiesOf('accounts:signInWithPhoneNumber').single,
        <String, Object?>{'sessionInfo': 'session-1', 'code': '123456'},
      );
    });

    test(
      'a phone credential sends the temporary proof and the number',
      () async {
        backend.on('accounts:signInWithPhoneNumber', (
          Map<String, Object?> body,
        ) {
          backend.accounts['u'] = <String, Object?>{
            'phoneNumber': '+15555550100',
          };
          return jsonResponse(backend.tokensFor('u', provider: 'phone'));
        });

        await auth.signInWithCredential(
          PhoneAuthCredential.fromJson(
            '{"providerId":"phone","phoneNumber":"+15555550100",'
            '"temporaryProof":"proof-1"}',
          )!,
        );

        expect(
          backend.bodiesOf('accounts:signInWithPhoneNumber').single,
          <String, Object?>{
            'temporaryProof': 'proof-1',
            'phoneNumber': '+15555550100',
          },
        );
      },
    );
  });
}
