// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

class MultipleStringOption extends Option<List<String>> {
  MultipleStringOption({
    @required String question,
    @required int fieldsCount,
    @required IndexedFieldBuilder fieldBuilder,
    @required MultipleStringOptionValidator validator,
  })  : assert(fieldsCount > 0 || fieldsCount == -1),
        _fieldsCount = fieldsCount,
        _fieldBuilder = fieldBuilder,
        _validator = validator,
        _result = <String>[],
        super(question);

  final MultipleStringOptionValidator _validator;
  final IndexedFieldBuilder _fieldBuilder;
  final List<String> _result;

  /// A values of -1 indicate that there is an unlimited number of fields and that we return the result once the user
  /// submits an empty response
  final int _fieldsCount;

  bool get unlimitedFields => _fieldsCount == -1;

  @override
  int showField() {
    final String field = _fieldBuilder(_result.length);
    final int lines = const LineSplitter().convert(field).length;
    console.print(field);
    return lines;
  }

  @override
  void onAnswer(String response) {
    if (unlimitedFields && response.isNotEmpty || _result.length < _fieldsCount - 1) {
      _result.add(response);
      askQuestion();
    } else {
      if (!unlimitedFields) {
        _result.add(response);
      }
      complete(_result);
    }
  }

  @override
  String validate(String response) {
    return _validator(_result.length, response);
  }
}
