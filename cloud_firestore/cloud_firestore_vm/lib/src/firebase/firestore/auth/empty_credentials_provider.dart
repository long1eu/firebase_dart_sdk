// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:rxdart/rxdart.dart';

import 'credentials_provider.dart';
import 'user.dart';

/// A Credentials Provider that always returns an empty token
class EmptyCredentialsProvider extends CredentialsProvider {
  // ignore: close_sinks
  final BehaviorSubject<User> _onChange =
      BehaviorSubject<User>.seeded(User.unauthenticated);

  @override
  Future<String> get token => Future<String>.value(null);

  @override
  void invalidateToken() {}

  @override
  Stream<User> get onChange => _onChange;
}
