import 'store.dart';

/// Outside a browser there is no `localStorage`.
final class LocalStorageStore implements ErrorReportingStore {
  /// Throws an [UnsupportedError].
  LocalStorageStore(String _) {
    throw UnsupportedError(
      'ErrorReportingStore.localStorage is only available in a browser.',
    );
  }

  @override
  Future<ErrorReportingState> load() => throw UnimplementedError();

  @override
  Future<void> save(ErrorReportingState state) => throw UnimplementedError();
}
