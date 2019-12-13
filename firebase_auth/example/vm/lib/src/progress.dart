// File created by
// Lung Razvan <long1eu>
// on 11/12/2019

part of firebase_auth_example;

final List<String> progressChars = <String>['⣷', '⣯', '⣟', '⡿', '⢿', '⣻', '⣽', '⣾'];

final List<Progress> _currentProgresses = <Progress>[];

Future<void> _stopAllProgress() async {
  for (int i = 0; i < _currentProgresses.length; i++) {
    await _currentProgresses[i].cancel();
  }
}

class Progress {
  Progress(this.title, [this.rate = const Duration(milliseconds: 96)]) : _completer = Completer<void>() {
    _currentProgresses.add(this);
  }

  final String title;
  final Duration rate;
  final Completer<void> _completer;
  Timer _timer;
  DateTime _start;

  void show() {
    _start = DateTime.now();
    _printAt(0);
    _timer = Timer.periodic(rate, (Timer i) {
      console.print('print');
      _printAt(i.tick % progressChars.length);
    });
  }

  Future<void> cancel({bool removeLine = true}) {
    final Duration difference = _start.difference(DateTime.now());

    if (difference < const Duration(milliseconds: 1000)) {
      Timer(difference, () => _close(removeLine: removeLine));
    } else {
      _close(removeLine: removeLine);
    }

    return _completer.future;
  }

  void _printAt(int index) {
    console
      ..removeLastLine()
      ..print(progressChars[index])
      ..print(' $title');
  }

  void _close({bool removeLine = true}) {
    _currentProgresses.remove(this);
    if (removeLine) {
      console.removeLastLine();
    }
    _timer.cancel();
    _completer.complete();
  }
}
