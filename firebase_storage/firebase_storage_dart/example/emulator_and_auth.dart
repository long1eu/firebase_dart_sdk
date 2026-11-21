// The emulator and a signed-in user.
//
// The bucket demo-test-auth.appspot.com has rules that need request.auth:
// users/<uid>/ belongs to its owner, shared/ to any signed-in user. The
// emulator does not check tokens; mockUserToken makes the client send one
// that the rules see as the user.

import 'dart:convert';

import 'package:firebase_storage_dart/firebase_storage_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseStorage anonymous = emulatorStorage(bucket: authBucket);
  final FirebaseStorage alice = emulatorStorage(
    bucket: authBucket,
    mockUserToken: _unsignedToken('alice'),
    appName: 'alice',
  );
  final FirebaseStorage bob = emulatorStorage(
    bucket: authBucket,
    mockUserToken: _unsignedToken('bob'),
    appName: 'bob',
  );

  final Future<void> Function() cleanup = _cleanupOf(alice);
  await alice.ref('users/alice/note.txt').putString('mine');
  print('alice writes users/alice: ok');

  await _try('bob writes users/alice', () {
    return bob.ref('users/alice/other.txt').putString('x');
  });
  await _try('anonymous reads users/alice', () {
    return anonymous.ref('users/alice/note.txt').getBytes();
  });
  await bob.ref('shared/bob.txt').putString('for everybody');
  print('bob writes shared/: ok');

  await cleanup();
  for (final FirebaseStorage storage in <FirebaseStorage>[
    anonymous,
    alice,
    bob,
  ]) {
    storage.close();
  }
}

Future<void> Function() _cleanupOf(FirebaseStorage alice) => () async {
  await alice.ref('users/alice/note.txt').delete();
  await alice.ref('shared/bob.txt').delete();
};

Future<void> _try(String what, Future<Object?> Function() action) async {
  try {
    await action();
    print('$what: ok');
  } on FirebaseStorageException catch (error) {
    print('$what: ${error.code}');
  }
}

/// The emulator reads the user id from an unsigned JWT; a real token comes
/// from firebase_auth_providers_dart.
String _unsignedToken(String uid) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none'})}.'
      '${part(<String, Object?>{'user_id': uid, 'sub': uid})}.';
}
