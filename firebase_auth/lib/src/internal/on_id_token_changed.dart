// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Signature for delivering notifications when authentication state changes.
///
/// [tokenResult] represents the [InternalTokenResult], which can be used to
/// obtain a cached access token.
@keepForSdk
typedef void OnIdTokenChanged(InternalTokenResult tokenResult);
