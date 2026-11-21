// The bookkeeping that lets the real-project harness leave the account as it
// found it: what each step changed, what has been undone, and what is left.

/// What a step changed and has to undo; returned by [CleanupLedger.register].
final class CleanupToken {
  CleanupToken._(this.description);

  /// What the undo does, for the report (`unlink github.com`).
  final String description;
}

/// The undo actions of the changes the harness made to the account.
///
/// A step registers the undo right after its change, and runs it through
/// [run] when it is done. Whatever is still pending at the end (a step failed
/// in between) runs in [runPending], newest first, and what fails there, with
/// what can only be undone by hand ([recordManual]), is in [problems].
class CleanupLedger {
  final Map<CleanupToken, Future<void> Function()> _pending =
      <CleanupToken, Future<void> Function()>{};
  final List<String> _failures = <String>[];
  final List<String> _manual = <String>[];

  /// The descriptions of the undo actions not run successfully yet, oldest
  /// first.
  List<String> get pending => <String>[
    for (final CleanupToken token in _pending.keys) token.description,
  ];

  /// What is left on the account: the undo actions that failed in
  /// [runPending] with their error, then what can only be undone by hand.
  List<String> get problems => <String>[..._failures, ..._manual];

  /// Records that [undo] reverts a change just made.
  CleanupToken register(String description, Future<void> Function() undo) {
    final CleanupToken token = CleanupToken._(description);
    _pending[token] = undo;
    return token;
  }

  /// Runs the undo of [token] now. On success it is no longer pending; on
  /// failure the error is rethrown and the undo stays pending, so that
  /// [runPending] tries it once more.
  Future<void> run(CleanupToken token) async {
    final Future<void> Function()? undo = _pending[token];
    if (undo == null) {
      return;
    }
    await undo();
    _pending.remove(token);
  }

  /// Records a change the harness cannot undo (it never deletes an account).
  void recordManual(String description) => _manual.add(description);

  /// Runs every pending undo once, newest first. [describeError] turns an
  /// error into the text of [problems].
  Future<void> runPending(String Function(Object error) describeError) async {
    for (final CleanupToken token in _pending.keys.toList().reversed) {
      try {
        await run(token);
      } on Object catch (e) {
        _pending.remove(token);
        _failures.add('${token.description}: ${describeError(e)}');
      }
    }
  }
}
