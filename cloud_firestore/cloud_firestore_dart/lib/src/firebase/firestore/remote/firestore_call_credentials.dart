// File created by
// Lung Razvan <long1eu>
// on 24/09/2018
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/app_check_token_provider.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:grpc/grpc.dart';

class FirestoreCallCredentials {
  const FirestoreCallCredentials(this.credentialsProvider,
      {this.appCheckProvider});

  static const String tag = 'FirestoreCallCredentials';

  static const String _authorizationHeader = 'Authorization';
  static const String _appCheckHeader = 'x-firebase-appcheck';

  final CredentialsProvider credentialsProvider;
  final AppCheckTokenProvider? appCheckProvider;

  Future<void> getRequestMetadata(
      Map<String, String> metadata, String uri) async {
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
    } catch (e, stackTrace) {
      Log.w(tag, 'Failed to get AppCheck token: $e. $stackTrace');
      throw GrpcError.unauthenticated(e.toString());
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
      Log.w(tag, 'Failed to get token: $e. $stackTrace');
      throw GrpcError.unauthenticated(e.toString());
    }
  }
}
