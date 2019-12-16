// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

class MultipleOptions extends Option<int> {
  MultipleOptions({
    @required String question,
    @required int optionsCount,
    @required IndexedFieldBuilder builder,
    IndexedFieldBuilder descriptionBuilder,
    FieldBuilder fieldBuilder,
    @required SimpleOptionValidator<String> validator,
  })  : _optionsCount = optionsCount,
        _builder = builder,
        _descriptionBuilder = descriptionBuilder,
        _fieldBuilder = fieldBuilder,
        _validator = validator,
        super(question);

  final int _optionsCount;
  final IndexedFieldBuilder _builder;
  final IndexedFieldBuilder _descriptionBuilder;
  final FieldBuilder _fieldBuilder;
  final SimpleOptionValidator<String> _validator;

  @override
  void printQuestion() {
    console.println(question);
    for (int i = 0; i <= _optionsCount; i++) {
      console //
        ..printTabbed()
        ..print('(${i + 1})'.padLeft(4, ' '))
        ..print(': ')
        ..println(i == _optionsCount ? 'Exit' : _builder(i));
    }

    console.println();
  }

  @override
  int showField() {
    if (_descriptionBuilder != null) {
      console
        ..println('You can use @<number> to get more info. For example: ${'@1'.bold.cyan.reset}')
        ..print(_fieldBuilder?.call() ?? 'Option: ');
      return 2;
    } else {
      console.print(_fieldBuilder?.call() ?? 'Option: ');
      return 1;
    }
  }

  @override
  String validate(String response) {
    return _validator(response);
  }

  @override
  void onAnswer(String response) {
    String value = response;
    bool isDescription = false;
    if (value.startsWith('@')) {
      isDescription = true && _descriptionBuilder != null;
      value = value.substring(1);
    }

    final int option = int.tryParse(value);
    final int exitOption = _optionsCount + 1;
    if (isDescription) {
      _printDescription(option);
      askQuestion();
      return;
    } else {
      _completer.complete(option == exitOption ? -1 : option - 1);
    }
  }

  void _printDescription(int option) {
    console
      ..moveUp()
      ..removeLastLine()
      ..moveUp()
      ..removeLastLine()
      ..println('${'($option)'.cyan.bold} ${_builder(option - 1).reset}: ${_descriptionBuilder(option - 1)}')
      ..println();
  }
}
