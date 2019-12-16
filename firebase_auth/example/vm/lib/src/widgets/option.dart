// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

/// Signature for validating a user response for a specific field
typedef MultipleStringOptionValidator = String Function(int fieldIndex, String response);

/// Signature for building a field for a specific index
typedef IndexedFieldBuilder = String Function(int index);

/// Signature for validating a user response
typedef SimpleOptionValidator<T> = String Function(T response);

/// Signature for building a field
typedef FieldBuilder = String Function();

abstract class Option<Result> {
  Option(this.question) : _completer = Completer<Result>();

  final String question;
  final Completer<Result> _completer;

  bool _hadRetry = false;
  int _lines = 1;

  /// Always return super.show(); This will wait for the users final response and return it in the Future
  @mustCallSuper
  Future<Result> show() {
    printQuestion();
    Future<void>(askQuestion);
    return _completer.future;
  }

  /// Override this if you want to print more then the [question].
  void printQuestion() {
    console //
      ..println(question)
      ..println();
  }

  /// Print the question you want the user to answer to.
  ///
  /// This should not contain line breaks.
  /// Return the number of lines written
  int showField();

  /// Called when the user submits a valid answer.
  void onAnswer(String response);

  /// Called to validate the answer
  String validate(String response);

  /// Completes the Future returned by [show] with the supplied values.
  void complete([Result value]) {
    _completer.complete(value);
  }

  /// Called when the answer provided by the user is not valid.
  void _retry(String error) {
    if (_hadRetry) {
      // if this is not the first try then we have an extra line
      console.removeLines();
    }

    _hadRetry = true;
    console //
      ..removeLines(_lines)
      ..println(error);
    askQuestion();
  }

  void askQuestion() {
    _lines = showField();
    _readAnswer();
  }

  Future<void> _readAnswer() async {
    final String response = await console.nextLine;
    final String error = validate(response);
    if (error != null) {
      _retry(error);
    } else {
      onAnswer(response);
    }
  }
}
