// File created by
// Lung Razvan <long1eu>
// on 24/09/2018
import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/auth/credentials_provider.dart';
import 'package:firebase_core_vm/firebase_core_vm.dart';
import 'package:grpc/grpc.dart';

class FirestoreCallCredentials {
  const FirestoreCallCredentials(this.credentialsProvider);

  static const String tag = 'FirestoreCallCredentials';

  static const String _authorizationHeader = 'Authorization';

  final CredentialsProvider credentialsProvider;

  Future<void> getRequestMetadata(Map<String, String> metadata, String uri) async {
    try {
      final String token = await credentialsProvider.token;
      if (token != null && token.isNotEmpty) {
        Log.d(tag, 'Successfully fetched token.');
        metadata[_authorizationHeader] = 'Bearer $token';
      }
    } on FirebaseApiNotAvailableError catch (_) {
      Log.d(tag, 'Firebase Auth API not available, not using authentication.');
    } on FirebaseNoSignedInUserError catch (_) {
      Log.d(tag, 'No user signed in, not using authentication.');
    } catch (e) {
      Log.w(tag, 'Failed to get token: $e. ${e.stackTrace}');
      throw GrpcError.unauthenticated(e.toString());
    }
  }
}
