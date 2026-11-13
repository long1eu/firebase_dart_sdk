import 'dart:async';

/// Lists the addresses of the network interfaces of the machine, as opaque
/// strings (for example `en0/192.168.1.20`).
typedef AddressLister = Future<Set<String>> Function();

/// Creates a timer; replaced in tests.
typedef TimerFactory = Timer Function(Duration delay, void Function() callback);

/// Notices that the connectivity of the machine *may* have come back, so that
/// the client can retry its streams right away instead of waiting for their
/// backoff.
///
/// It never says that the client is offline, and nothing may conclude that
/// from it: an interface that is up does not mean that Firestore is reachable,
/// and one that is down does not mean that it is not. A failed stream remains
/// the only source of the offline state. A signal that turns out to be wrong
/// costs one connection attempt.
///
/// Two things are taken as a hint, while [start]ed:
///   * an address appears on a network interface (Wi-Fi joined again, a cable
///     plugged in, a VPN that came up, a new DHCP lease);
///   * the wall clock jumped ahead of the timer, which is what happens when the
///     machine was asleep.
///
/// The detector only runs while the client has a stream that failed (see
/// `RemoteStore`): a healthy client has no timer.
///
/// PORTING NOTE: the Android SDK registers a network callback with the system
/// (`AndroidConnectivityMonitor`). `dart:io` has no such event, so the port
/// polls the interface list, and only while it would make a difference.
class ConnectivityChangeDetector {
  /// Creates a detector that reads the interfaces with [listAddresses].
  ConnectivityChangeDetector({
    required AddressLister listAddresses,
    this.pollInterval = const Duration(seconds: 2),
    this.wakeThreshold = const Duration(seconds: 10),
    this.minSignalInterval = const Duration(seconds: 5),
    DateTime Function()? now,
    TimerFactory? createTimer,
  }) : _listAddresses = listAddresses,
       _now = now ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new;

  final AddressLister _listAddresses;
  final DateTime Function() _now;
  final TimerFactory _createTimer;

  /// How often the interfaces are read while the detector is started.
  final Duration pollInterval;

  /// How much later than planned a poll must run to be taken as a wake-up
  /// from sleep.
  final Duration wakeThreshold;

  /// The minimum time between two signals, so that a flapping interface
  /// cannot make the client reconnect in a tight loop.
  final Duration minSignalInterval;

  /// Called when the connectivity may have come back.
  void Function()? onChange;

  Timer? _timer;
  Set<String>? _addresses;
  DateTime? _lastPoll;
  DateTime? _lastSignal;
  bool _disposed = false;

  /// Incremented by every [start] and [stop], so that a poll that is waiting
  /// for the interface list knows that it was overtaken.
  int _generation = 0;

  /// Whether the detector is polling.
  bool get isRunning => _timer != null;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// Starts polling. The addresses of this moment are the baseline: only an
  /// address that appears later is a hint. Does nothing when already started
  /// or disposed.
  void start() {
    if (_disposed || isRunning) {
      return;
    }
    _generation++;
    _addresses = null;
    _lastPoll = _now();
    _schedule();
    _readBaseline(_generation);
  }

  /// Stops polling and forgets the baseline.
  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _addresses = null;
    _lastPoll = null;
  }

  /// Stops polling for good; [start] does nothing afterwards.
  void dispose() {
    stop();
    _disposed = true;
    onChange = null;
  }

  void _schedule() {
    _timer = _createTimer(pollInterval, _poll);
  }

  Future<void> _readBaseline(int generation) async {
    final Set<String>? addresses = await _safeList();
    if (generation != _generation || addresses == null) {
      return;
    }
    // A poll that ran first already set the baseline.
    _addresses ??= addresses;
  }

  Future<void> _poll() async {
    final int generation = _generation;
    final DateTime now = _now();
    final DateTime? lastPoll = _lastPoll;
    _lastPoll = now;
    _schedule();

    // The timer does not run while the machine sleeps: a poll that is much
    // later than planned means that it just woke up.
    bool changed =
        lastPoll != null &&
        now.difference(lastPoll) > pollInterval + wakeThreshold;

    final Set<String>? addresses = await _safeList();
    if (generation != _generation) {
      return;
    }
    if (addresses != null) {
      final Set<String>? previous = _addresses;
      _addresses = addresses;
      // Only an address that appeared is a hint. One that went away tells
      // nothing about whether the backend can be reached now.
      if (previous != null && addresses.difference(previous).isNotEmpty) {
        changed = true;
      }
    }

    if (changed) {
      final DateTime? lastSignal = _lastSignal;
      if (lastSignal == null ||
          now.difference(lastSignal) >= minSignalInterval) {
        _lastSignal = now;
        onChange?.call();
      }
    }
  }

  /// The interface list, or null when it cannot be read (which is not a hint).
  Future<Set<String>?> _safeList() async {
    try {
      return await _listAddresses();
    } catch (_) {
      return null;
    }
  }
}
