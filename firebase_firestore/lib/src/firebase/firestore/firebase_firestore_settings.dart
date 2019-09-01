// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Settings used to configure a FirebaseFirestore instance.
@publicApi
class FirebaseFirestoreSettings {
  /// Constructs a FirebaseFirestoreSettings object
  FirebaseFirestoreSettings({
    this.host = _defaultHost,
    this.sslEnabled = true,
    this.persistenceEnabled = true,
  })  : assert(host != null, 'Provided host must not be null.'),
        assert(
            !(!sslEnabled && host == _defaultHost),
            'You can\'t set the \'sslEnabled\' setting '
            'unless you also set a non-default \'host\'.');

  static const String _defaultHost = 'firestore.googleapis.com';

  /// The host of the Firestore backend.
  @publicApi
  final String host;

  /// Enables or disables SSL for communication. The default is to use SSL.
  @publicApi
  final bool sslEnabled;

  /// Enables or disables local persistent storage. The default is to use local
  /// persistent storage.
  @publicApi
  final bool persistenceEnabled;

  FirebaseFirestoreSettings copyWith({
    String host,
    bool sslEnabled,
    bool persistenceEnabled,
  }) {
    return FirebaseFirestoreSettings(
      host: host ?? this.host,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      persistenceEnabled: persistenceEnabled ?? this.persistenceEnabled,
    );
  }

  @override
  String toString() {
    return (ToStringHelper(FirebaseFirestoreSettings)
          ..add('host', host)
          ..add('sslEnabled', sslEnabled)
          ..add('persistenceEnabled', persistenceEnabled))
        .toString();
  }
}
