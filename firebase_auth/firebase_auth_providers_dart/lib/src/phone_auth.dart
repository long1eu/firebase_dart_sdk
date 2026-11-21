// The provider id and sign-in method names are FlutterFire's (and the JS SDK's) constants, in their
// upper case.
// ignore_for_file: constant_identifier_names

import 'package:firebase_auth_providers_dart/src/auth_credential.dart';
import 'package:firebase_auth_providers_dart/src/auth_exception.dart';
import 'package:firebase_auth_providers_dart/src/firebase_user_auth.dart';

/// Makes the credential of a phone number verified by an SMS code (`FIRPhoneAuthProvider` of the
/// iOS SDK, `PhoneAuthProvider` of the JS SDK and of FlutterFire).
///
/// [FirebaseUserAuth.verifyPhoneNumber] sends the code and returns a verification id; [credential]
/// pairs that id with the code the user typed in, for [FirebaseUserAuth.signInWithCredential],
/// [FirebaseUserAuth.linkWithCredential], [FirebaseUserAuth.reauthenticateWithCredential] and
/// [FirebaseUserAuth.updatePhoneNumber]. The same pair finishes an SMS second factor
/// ([FirebaseUserAuth.finalizePhoneEnrollment], `MultiFactorResolver.resolveSignInWithPhone`).
///
/// ```dart
/// final String verificationId = await auth.verifyPhoneNumber(
///   '+15555550100',
///   appVerification: AppVerification.recaptchaV2Loopback(),
/// );
/// final String code = await askTheUserForTheCode(); // your own code field
/// await auth.signInWithCredential(
///   PhoneAuthProvider.credential(verificationId: verificationId, verificationCode: code),
/// );
/// ```
abstract final class PhoneAuthProvider {
  /// The provider id: `phone`.
  static const String PROVIDER_ID = 'phone';

  /// The sign-in method of a phone number: `phone`.
  static const String PHONE_SIGN_IN_METHOD = 'phone';

  /// The credential of [verificationId] (what [FirebaseUserAuth.verifyPhoneNumber] returned) and
  /// [verificationCode] (the code of the SMS), like
  /// `credential(withVerificationID:verificationCode:)` of the iOS SDK. Nothing is checked until
  /// the credential is used.
  static PhoneAuthCredential credential({
    required String verificationId,
    required String verificationCode,
  }) => PhoneAuthCredential._(
    verificationId: verificationId,
    verificationCode: verificationCode,
  );
}

/// A credential of the phone provider (`FIRPhoneAuthCredential` of the iOS SDK), in one of two
/// forms:
///
/// * a verification id and the code of its SMS ([verificationId], [verificationCode]): make it with
///   [PhoneAuthProvider.credential];
/// * a temporary proof of a verified phone number ([temporaryProof], [phoneNumber]): the backend
///   hands one out when a link or an update finds the number on another account, and
///   [FirebaseAuthException.credential] of that `credential-already-in-use` error carries it, so
///   that [FirebaseUserAuth.signInWithCredential] with it signs in to that account (as in the iOS
///   SDK).
///
/// Every value is a secret: [toString] leaves them out, and no error message of this package quotes
/// them.
class PhoneAuthCredential extends AuthCredential {
  const PhoneAuthCredential._({
    this.verificationId,
    this.verificationCode,
    this.temporaryProof,
    this.phoneNumber,
  }) : super(
         providerId: PhoneAuthProvider.PROVIDER_ID,
         signInMethod: PhoneAuthProvider.PHONE_SIGN_IN_METHOD,
       );

  /// The verification id of [FirebaseUserAuth.verifyPhoneNumber] (the `sessionInfo` of the REST
  /// API); null for a temporary proof. Not part of [toString].
  final String? verificationId;

  /// The code of the SMS; null for a temporary proof. Not part of [toString].
  final String? verificationCode;

  /// The temporary proof the backend returned for [phoneNumber]; null for a verification id and
  /// code. Not part of [toString].
  final String? temporaryProof;

  /// The verified phone number of a temporary proof; null otherwise. Not part of [toString].
  final String? phoneNumber;

  /// The credential in the JSON shape of the JS SDK's `toJSON`, which [fromJson] here and
  /// `PhoneAuthCredential.fromJSON` of the JS SDK read back: `providerId` (`phone`), then
  /// `phoneNumber`, `temporaryProof`, `verificationCode` and `verificationId` when they are set and
  /// not empty.
  ///
  /// The map holds the code of the SMS or the temporary proof and the phone number: keep it as
  /// secret as they are.
  Map<String, Object?> toJson() => <String, Object?>{
    'providerId': providerId,
    'phoneNumber': ?_nonEmptyString(phoneNumber),
    'temporaryProof': ?_nonEmptyString(temporaryProof),
    'verificationCode': ?_nonEmptyString(verificationCode),
    'verificationId': ?_nonEmptyString(verificationId),
  };

  /// Reads the JSON of [toJson] or of the JS SDK's `toJSON` (`PhoneAuthCredential.fromJSON`):
  /// [json] is the map, or its JSON text. Both forms read back: a verification id with its code,
  /// and a temporary proof with its phone number (the [FirebaseAuthException.credential] of
  /// `credential-already-in-use`).
  ///
  /// As in the JS SDK, `providerId` is not looked at, an empty value counts as missing, and the
  /// result is null when `verificationId`, `verificationCode`, `phoneNumber` and `temporaryProof`
  /// are all missing; text that is not JSON throws (a [FormatException] here, as `JSON.parse`
  /// throws there). Like the JS SDK, it does not check that the values make one of the two forms: a
  /// credential without one fails when it is used. Unlike the JS SDK, the result is also null when
  /// [json] is not a map or one of the four fields is there and not a string.
  static PhoneAuthCredential? fromJson(Object json) {
    final Map<Object?, Object?>? map = credentialJsonMap(json);
    if (map == null ||
        _phoneJsonKeys.any((String key) => map[key] is! String?)) {
      return null;
    }
    final String? verificationId = _nonEmptyString(map['verificationId']);
    final String? verificationCode = _nonEmptyString(map['verificationCode']);
    final String? temporaryProof = _nonEmptyString(map['temporaryProof']);
    final String? phoneNumber = _nonEmptyString(map['phoneNumber']);
    if (verificationId == null &&
        verificationCode == null &&
        temporaryProof == null &&
        phoneNumber == null) {
      return null;
    }
    return PhoneAuthCredential._(
      verificationId: verificationId,
      verificationCode: verificationCode,
      temporaryProof: temporaryProof,
      phoneNumber: phoneNumber,
    );
  }
}

/// The keys of the JSON of a [PhoneAuthCredential] that hold an optional string.
const List<String> _phoneJsonKeys = <String>[
  'verificationId',
  'verificationCode',
  'temporaryProof',
  'phoneNumber',
];

/// [value] when it is a string that is not empty, else null (`value || undefined` of the JS SDK).
String? _nonEmptyString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// The credential of a temporary proof of the backend, or null when [response] has none. Not
/// exported.
PhoneAuthCredential? phoneCredentialFromProof(Map<String, Object?> response) {
  final Object? proof = response['temporaryProof'];
  final Object? number = response['phoneNumber'];
  if (proof is! String ||
      proof.isEmpty ||
      number is! String ||
      number.isEmpty) {
    return null;
  }
  return PhoneAuthCredential._(temporaryProof: proof, phoneNumber: number);
}

/// What replaces a secret in the text of an error.
const String _redacted = '<redacted>';

/// Secrets shorter than this are not looked for in the text of an error: a one-letter code would
/// cut every word it appears in.
const int _shortestSecret = 6;

/// A run of digits joined by at most three characters that are neither letters nor digits (spaces,
/// non-breaking spaces, dashes of any kind, slashes, dots, brackets), with an optional `+` or `(`
/// before it: how a phone number is written. `<` and `>` end a run, so that a `<redacted>` marker
/// stays whole, and so does [_kept], the stand-in of a span that is left alone.
final RegExp _digitRun = RegExp(
  r'[+(]?\d(?:[^\p{L}\p{N}<>\uE000]{1,3}\d|\d)*',
  unicode: true,
);

/// What stands in for a span of [_leftAlone] while the digit runs are cut.
const String _kept = '\uE000';

/// Digits that are not a phone number: a URL, the number after `project` or `projects/`, a date
/// (with a time), an IPv4 address (with a port).
final RegExp _leftAlone = RegExp(
  r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+'
  r'|(?<=\bprojects?[\s/:=#]{0,3})\d+'
  r'|(?<!\d)(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}(?:[ T]\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?'
  r'|\d{1,2}[-/.]\d{1,2}[-/.]\d{4}'
  r'|\d{1,3}(?:\.\d{1,3}){3}(?::\d{1,5})?)(?!\d)',
  caseSensitive: false,
);

/// [error] without any of [secrets] (a phone number, a verification id, an SMS code, a reCAPTCHA
/// token), for the errors of the phone requests. In [FirebaseAuthException.message] and
/// [FirebaseAuthException.serverCode]:
///
/// * each secret of six characters or more is replaced by `<redacted>` where it stands as a whole
///   token (not inside a longer word), a phone number also in its digits-only form;
/// * then anything shaped like a phone number (seven digits or more, with any separators between
///   them), such as the number of an SMS second factor, which the client knows only masked. Digits
///   inside a URL, after `project` or `projects/`, and IPv4 addresses and dates are left alone.
///
/// [FirebaseAuthException.phoneNumber] and [FirebaseAuthException.serverResponse] are dropped;
/// [FirebaseAuthException.credential] is kept (its `toString` shows no secret). A
/// [FirebaseAuthMultiFactorException] is returned as it is: its message is one of the package's,
/// and its hints carry masked phone numbers only. Not exported.
FirebaseAuthException redactPhoneSecrets(
  FirebaseAuthException error,
  Iterable<String?> secrets,
) {
  if (error is FirebaseAuthMultiFactorException) {
    return error;
  }
  final List<RegExp> tokens = <RegExp>[
    for (final String form in _formsOf(secrets))
      RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(form)}(?![\\p{L}\\p{N}])',
        unicode: true,
      ),
  ];
  String scrub(String text) {
    for (final RegExp token in tokens) {
      text = text.replaceAll(token, _redacted);
    }
    return _scrubPhoneShaped(text);
  }

  final String? serverCode = error.serverCode;
  return FirebaseAuthException(
    code: error.code,
    message: scrub(error.message),
    serverCode: serverCode == null ? null : scrub(serverCode),
    httpStatus: error.httpStatus,
    email: error.email,
    tenantId: error.tenantId,
    credential: error.credential,
    cause: error.cause,
  );
}

/// [text] with every run of seven digits or more replaced by `<redacted>`, except the spans of
/// [_leftAlone]: those are swapped for a stand-in that ends a run (a letter code between two
/// [_kept] marks), and put back afterwards.
String _scrubPhoneShaped(String text) {
  final List<String> kept = <String>[];
  final String masked = text.replaceAllMapped(_leftAlone, (Match m) {
    kept.add(m[0]!);
    return '$_kept${_letters(kept.length - 1)}$_kept';
  });
  final String cut = masked.replaceAllMapped(
    _digitRun,
    (Match m) =>
        m[0]!.replaceAll(RegExp(r'\D'), '').length < 7 ? m[0]! : _redacted,
  );
  return cut.replaceAllMapped(
    RegExp('$_kept([a-z]+)$_kept'),
    (Match m) => kept[_index(m[1]!)],
  );
}

/// [index] written in the letters a to z (0 is `a`, 26 is `ba`).
String _letters(int index) {
  String code = '';
  do {
    code = String.fromCharCode(0x61 + index % 26) + code;
    index ~/= 26;
  } while (index > 0);
  return code;
}

/// The index that [_letters] wrote as [code].
int _index(String code) {
  int index = 0;
  for (final int unit in code.codeUnits) {
    index = index * 26 + unit - 0x61;
  }
  return index;
}

/// The [secrets] of six characters or more and, for a phone number (one that starts with `+`), its
/// digits alone (it may come back without its `+` and spaces); longest first, so that a secret
/// inside another is replaced after it.
List<String> _formsOf(Iterable<String?> secrets) {
  final Set<String> forms = <String>{};
  for (final String? secret in secrets) {
    if (secret == null || secret.length < _shortestSecret) {
      continue;
    }
    forms.add(secret);
    final String digits = secret.replaceAll(RegExp(r'\D'), '');
    if (secret.startsWith('+') && digits.length >= _shortestSecret) {
      forms.add(digits);
    }
  }
  return forms.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
}
