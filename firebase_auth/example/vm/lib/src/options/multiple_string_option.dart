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
  })  : _fieldsCount = fieldsCount,
        _fieldBuilder = fieldBuilder,
        _validator = validator,
        _result = <String>[],
        super(question);

  final MultipleStringOptionValidator _validator;
  final IndexedFieldBuilder _fieldBuilder;
  final List<String> _result;
  final int _fieldsCount;

  @override
  int showField() {
    console.print(_fieldBuilder(_result.length));
    return 1;
  }

  @override
  void onAnswer(String response) {
    if (_result.length < _fieldsCount - 1) {
      _result.add(response);
      askQuestion();
    } else {
      _result.add(response);
      complete(_result);
    }
  }

  @override
  String validate(String response) {
    return _validator(_result.length, response);
  }
}
