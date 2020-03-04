// File created by
// Lung Razvan <long1eu>
// on 10/12/2019

part of firebase_auth_vm;

class SequentialRunner {
  SequentialRunner() : _tasks = Queue<_TaskQueueEntry<void>>();

  final Queue<_TaskQueueEntry<void>> _tasks;

  Completer<void> _recentActiveCompleter;

  Future<T> enqueue<T>(Task<T> function) async {
    final _TaskQueueEntry<T> taskEntry = _TaskQueueEntry<T>(function);

    final bool listWasEmpty = _tasks.isEmpty;
    _tasks.add(taskEntry);

    if (_recentActiveCompleter == null || _recentActiveCompleter.isCompleted && listWasEmpty) {
      _runNext();
    }

    return taskEntry.completer.future;
  }

  /// Runs the next available [Task] in the queue.
  void _runNext() {
    if (_tasks.isNotEmpty) {
      final _TaskQueueEntry<dynamic> taskEntry = _tasks.first;
      _recentActiveCompleter = taskEntry.completer;

      taskEntry.function().then((dynamic value) {
        Future<void>(() {
          _tasks.removeFirst();
          _runNext();
        });
        taskEntry.completer.complete(value);
      }).catchError((dynamic error) {
        Future<void>(() {
          _tasks.removeFirst();
          _runNext();
        });
        taskEntry.completer.completeError(error);
      });
    }
  }
}

class _TaskQueueEntry<T> {
  _TaskQueueEntry(this.function) : completer = Completer<T>();

  Task<T> function;
  Completer<T> completer;
}

typedef Task<T> = Future<T> Function();
