// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

import 'package:firebase_common/src/annotations.dart';

/// Event sent when data collection default changes its value.
@keepForSdk
class DataCollectionDefaultChange {
  /// The new value.
  @keepForSdk
  final bool enabled;

  @keepForSdk
  const DataCollectionDefaultChange({this.enabled});
}
