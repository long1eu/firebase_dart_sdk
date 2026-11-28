/// Firebase Data Connect for pure Dart: run the GraphQL queries and mutations of a connector, over
/// gRPC on the Dart VM and REST on the web.
///
/// Create a `DataConnect` for one connector of a `FirebaseApp`, then call operations by name,
/// untyped with `executeQuery` and `executeMutation`, or typed through `query` and `mutation`
/// references. Failures are `DataConnectException`s; GraphQL errors are a
/// `DataConnectOperationException` that keeps the data the server returned with them.
library;

export 'package:firebase_data_connect_dart/src/api/connector_config.dart'
    show CallerSdkType, ConnectorConfig;
export 'package:firebase_data_connect_dart/src/api/data_connect.dart'
    show DataConnect;
export 'package:firebase_data_connect_dart/src/api/refs.dart'
    show
        DataSource,
        MutationRef,
        MutationResult,
        OperationRef,
        QueryFetchPolicy,
        QueryRef,
        QueryResult;
export 'package:firebase_data_connect_dart/src/errors.dart'
    show
        DataConnectException,
        DataConnectOperationException,
        GraphqlError,
        SourceLocation;
