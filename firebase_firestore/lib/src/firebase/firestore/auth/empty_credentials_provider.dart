// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import '../util/listener.dart';
import 'credentials_provider.dart';
import 'user.dart';

/// A Credentials Provider that always returns an empty token
class EmptyCredentialsProvider extends CredentialsProvider {
  @override
  Future<String> get token => Future<String>.value('');

  @override
  void invalidateToken() {}

  @override
  void setChangeListener(Listener<User> changeListener) {
    changeListener(User.unauthenticated);
  }

  @override
  void removeChangeListener() {}
}
