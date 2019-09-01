// File created by
// Lung Razvan <long1eu>
// on 16/09/2018

class FirebaseError implements Error {
  const FirebaseError(this.message, [this.stackTrace])
      : assert(message != null, 'Detail message must not be empty.');

  final String message;

  @override
  final StackTrace stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}
