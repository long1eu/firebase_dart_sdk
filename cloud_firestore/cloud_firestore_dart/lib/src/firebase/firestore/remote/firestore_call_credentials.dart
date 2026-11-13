// File created by
// Lung Razvan <long1eu>
// on 24/09/2018
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/grpc_status.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/redact_tokens.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';

class FirestoreCallCredentials {
  const FirestoreCallCredentials(
    this.credentialsProvider, {
    this.appCheckProvider,
  });

  static const String tag = 'FirestoreCallCredentials';

  static const String _authorizationHeader = 'Authorization';
  static const String _appCheckHeader = 'x-firebase-appcheck';

  final CredentialsProvider credentialsProvider;
  final AppCheckTokenProvider? appCheckProvider;

  Future<void> getRequestMetadata(
    Map<String, String> metadata,
    String uri,
  ) async {
    // Both tokens are requested at the same time, like upstream. The auth
    // error wins over the App Check error.
    await Future.wait<void>(<Future<void>>[
      _applyAuth(metadata),
      _applyAppCheck(metadata),
    ]);
  }

  Future<void> _applyAppCheck(Map<String, String> metadata) async {
    final AppCheckTokenProvider? provider = appCheckProvider;
    if (provider == null) {
      return;
    }
    try {
      final String token = await provider.token;
      if (token.isNotEmpty) {
        Log.d(tag, 'Successfully fetched AppCheck token.');
        metadata[_appCheckHeader] = token;
      }
    } on FirebaseApiNotAvailableError catch (_) {
      Log.d(tag, 'Firebase AppCheck API not available.');
    } catch (e) {
      // The App Check SDKs never fail a token request: they report the
      // failure in the result together with a placeholder token, and Firestore
      // sends the request anyway (the backend decides, depending on whether
      // App Check is enforced). A provider that throws is treated the same
      // way: the request goes out without the header, and the failure is
      // logged. Failing the request instead would block every write and
      // listener on a project that does not enforce App Check.
      Log.w(
        tag,
        'Failed to get AppCheck token; sending the request without it. '
        'Error: ${redactTokens('$e')}',
      );
    }
  }

  Future<void> _applyAuth(Map<String, String> metadata) async {
    try {
      final String? token = await credentialsProvider.token;
      if (token != null && token.isNotEmpty) {
        Log.d(tag, 'Successfully fetched token.');
        metadata[_authorizationHeader] = 'Bearer $token';
      }
    } on FirebaseApiNotAvailableError catch (_) {
      Log.d(tag, 'Firebase Auth API not available, not using authentication.');
    } on FirebaseNoSignedInUserError catch (_) {
      Log.d(tag, 'No user signed in, not using authentication.');
    } catch (e, stackTrace) {
      // The text of the provider's error is logged and passed on with anything that looks like a token removed
      // (a provider may quote the token it could not use). The stack trace only goes to the debug log.
      final String message = redactTokens('$e');
      Log.w(tag, 'Failed to get token: $message');
      Log.d(tag, 'Failed to get token: $message. $stackTrace');
      throw GrpcError.unauthenticated(message);
    }
  }
}
