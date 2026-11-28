/// The API of FlutterFire's `firebase_data_connect` 0.4.2 that generated Data Connect code calls,
/// on top of this package's own client.
///
/// Generated code imports `package:firebase_data_connect/firebase_data_connect.dart`; on the VM
/// without Flutter, `dart run firebase_data_connect_dart:rewrite_generated <directory>` points it
/// at this library. Application code uses
/// `package:firebase_data_connect_dart/firebase_data_connect_dart.dart`; both define
/// `ConnectorConfig`, `QueryRef`, `MutationRef`, `QueryResult`, `QueryFetchPolicy` and
/// `DataSource`, so an application imports one of them, or the other with a prefix.
library;

export 'package:firebase_data_connect_dart/src/compat/any_value.dart'
    show AnyValue, defaultSerializer;
export 'package:firebase_data_connect_dart/src/compat/cache_types.dart'
    show CacheSettings, CacheStorage, QueryFetchPolicy;
export 'package:firebase_data_connect_dart/src/compat/connector_config.dart'
    show CallerSDKType, ConnectorConfig;
export 'package:firebase_data_connect_dart/src/compat/empty_serializer.dart'
    show emptySerializer;
export 'package:firebase_data_connect_dart/src/compat/errors.dart'
    show
        DataConnectError,
        DataConnectErrorCode,
        DataConnectFieldPathSegment,
        DataConnectListIndexPathSegment,
        DataConnectOperationError,
        DataConnectOperationFailureResponse,
        DataConnectOperationFailureResponseErrorInfo,
        DataConnectPathSegment,
        Deserializer,
        DynamicDeserializer,
        DynamicSerializer,
        Serializer;
export 'package:firebase_data_connect_dart/src/compat/firebase_data_connect.dart'
    show FirebaseDataConnect;
export 'package:firebase_data_connect_dart/src/compat/optional.dart'
    show
        Optional,
        OptionalState,
        listDeserializer,
        listSerializer,
        nativeFromJson,
        nativeToJson;
export 'package:firebase_data_connect_dart/src/compat/refs.dart'
    show
        DataSource,
        MutationRef,
        OperationRef,
        OperationResult,
        QueryRef,
        QueryResult;
export 'package:firebase_data_connect_dart/src/compat/timestamp.dart'
    show Timestamp;
