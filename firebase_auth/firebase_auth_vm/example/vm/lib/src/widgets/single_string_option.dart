// File created by
// Lung Razvan <long1eu>
// on 12/12/2019

part of firebase_auth_example;

class StringOption extends Option<String> {
  StringOption({
    @required String question,
    @required SimpleOptionValidator<String> validator,
    FieldBuilder fieldBuilder,
  })  : _validator = validator,
        _fieldBuilder = fieldBuilder,
        super(question);

  final SimpleOptionValidator<String> _validator;
  final FieldBuilder _fieldBuilder;

  @override
  int showField() {
    console.print(_fieldBuilder?.call() ?? 'Option: ');
    return 1;
  }

  @override
  String validate(String response) {
    return _validator(response);
  }

  @override
  void onAnswer(String response) {
    complete(response);
  }
}
