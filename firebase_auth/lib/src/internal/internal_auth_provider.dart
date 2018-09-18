// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_auth/src/internal/on_id_token_changed.dart';
import 'package:firebase_common/firebase_common.dart';

abstract class InternalAuthProvider extends InternalTokenProvider {
  @keepForSdk
  void addIdTokenObserver(OnIdTokenChanged observer);

  @keepForSdk
  void removeIdTokenObserver(OnIdTokenChanged observer);
}
