import 'dart:async';

import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_auth_secure_storage_dart/firebase_auth_secure_storage_dart.dart';

/// A [SecretStore] in memory that records its calls and fails on demand.
class FakeSecretStore implements SecretStore {
  /// The secrets by account.
  final Map<String, String> secrets = <String, String>{};

  /// The calls, as `read <account>`, `write <account>` or `delete <account>`.
  final List<String> calls = <String>[];

  /// Thrown by the next calls of that operation (`read`, `write`, `delete`)
  /// while set.
  final Map<String, Exception> failures = <String, Exception>{};

  /// What a read returns instead of the stored secret, while set.
  String? Function(String? stored)? readFilter;

  @override
  Future<String?> read(String account) async {
    calls.add('read $account');
    _fail('read');
    final String? stored = secrets[account];
    final String? Function(String? stored)? filter = readFilter;
    return filter == null ? stored : filter(stored);
  }

  @override
  Future<void> write(String account, String secret) async {
    calls.add('write $account');
    _fail('write');
    secrets[account] = secret;
  }

  @override
  Future<void> delete(String account) async {
    calls.add('delete $account');
    _fail('delete');
    secrets.remove(account);
  }

  void _fail(String operation) {
    final Exception? failure = failures[operation];
    if (failure != null) {
      throw failure;
    }
  }
}

/// An [AuthStorage] in memory that records its calls and fails on demand.
class FakeOldStorage implements AuthStorage {
  /// The values by key.
  final Map<String, String> values = <String, String>{};

  /// The calls, as `read <key>` or `write <key> <value or null>`.
  final List<String> calls = <String>[];

  /// Thrown by reads while set.
  Exception? readFailure;

  /// Thrown by writes while set.
  Exception? writeFailure;

  @override
  FutureOr<String?> read(String key) {
    calls.add('read $key');
    final Exception? failure = readFailure;
    if (failure != null) {
      throw failure;
    }
    return values[key];
  }

  @override
  FutureOr<void> write(String key, String? value) {
    calls.add('write $key ${value == null ? 'null' : 'value'}');
    final Exception? failure = writeFailure;
    if (failure != null) {
      throw failure;
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
