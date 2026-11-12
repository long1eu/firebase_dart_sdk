/// A tracker to keep a record of important details during database local
/// query execution. Port of `QueryContext` of the Android SDK.
class QueryContext {
  int _documentReadCount = 0;

  /// The number of documents passed through during local query execution.
  int get documentReadCount => _documentReadCount;

  void incrementDocumentReadCount(int count) {
    _documentReadCount += count;
  }
}
