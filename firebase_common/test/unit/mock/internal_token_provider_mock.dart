// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:async';

import 'package:firebase_common/src/auth/get_token_result.dart';
import 'package:firebase_common/src/internal/internal_token_provider.dart';

class InternalTokenProviderMock implements InternalTokenProvider {
  const InternalTokenProviderMock();

  static const InternalTokenProviderMock instance =
      const InternalTokenProviderMock();

  static const GetTokenResult accessTokenResult = const GetTokenResult('');
  static const String uidResult = 'uid';

  @override
  Future<GetTokenResult> getAccessToken(bool forceRefresh) {
    return Future<GetTokenResult>.delayed(
        const Duration(milliseconds: 500), () => accessTokenResult);
  }

  @override
  String get uid => uidResult;
}
