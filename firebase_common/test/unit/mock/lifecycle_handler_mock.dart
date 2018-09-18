// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/src/flutter/lifecycle_handler.dart';

class LifecycleHandlerMock implements LifecycleHandler {
  const LifecycleHandlerMock();

  static const LifecycleHandlerMock instance = const LifecycleHandlerMock();

  @override
  bool get isBackground => false;
}
