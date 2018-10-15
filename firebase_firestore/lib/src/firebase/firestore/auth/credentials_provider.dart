// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'user.dart';

/// A CredentialsProvider has a method to fetch an authorization token.
abstract class CredentialsProvider {
  /// Requests token for the current user. Use [invalidateToken] to
  /// force-refresh the token. Returns future that will be completed with the
  /// current token.
  Future<String> get token;

  /// Marks the last retrieved token as invalid, making the next [token]
  /// request force refresh the token.
  void invalidateToken();

  /// Stream that will receive credential changes (sign-in / sign-out, token
  /// changes). It is immediately called once with the initial user.
  Stream<User> get onChange;
}
