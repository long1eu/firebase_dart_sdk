import 'package:flutter/widgets.dart';

/// Whether the app is in use, from Flutter's [AppLifecycleListener], told to
/// every listener: `true` while the app is [AppLifecycleState.resumed] (in the
/// foreground and focused), `false` in every other state.
///
/// The package needs it before `runApp`, possibly before the binding exists:
/// [attach] does nothing until [WidgetsBinding.instance] is available, and the
/// package calls it again with each call of the platform interface, so the
/// listener starts with the first call after the binding is initialized.
/// Until then the clients count the app as active, their default.
final class AppActivity {
  AppActivity._();

  /// The one instance of the process.
  static final AppActivity instance = AppActivity._();

  final Set<ValueChanged<bool>> _listeners = <ValueChanged<bool>>{};

  AppLifecycleListener? _listener;

  bool? _active;

  /// The last state the binding reported, or null before it reported one.
  bool? get active => _active;

  /// Whether the [AppLifecycleListener] is in place.
  bool get isAttached => _listener != null;

  /// Calls [listener] with each change of [active] from now on.
  void addListener(ValueChanged<bool> listener) => _listeners.add(listener);

  /// Stops calling [listener].
  void removeListener(ValueChanged<bool> listener) =>
      _listeners.remove(listener);

  /// Starts listening to the binding when it exists and nothing listens yet,
  /// and takes the state it already has. Does nothing otherwise.
  void attach() {
    if (_listener != null) {
      return;
    }
    final WidgetsBinding? binding = _bindingOrNull();
    if (binding == null) {
      return;
    }
    _listener = AppLifecycleListener(
      binding: binding,
      onStateChange: _onStateChange,
    );
    final AppLifecycleState? state = binding.lifecycleState;
    if (state != null) {
      _onStateChange(state);
    }
  }

  void _onStateChange(AppLifecycleState state) {
    final bool active = state == AppLifecycleState.resumed;
    if (active == _active) {
      return;
    }
    _active = active;
    for (final ValueChanged<bool> listener in List<ValueChanged<bool>>.of(
      _listeners,
    )) {
      listener(active);
    }
  }

  /// Stops listening and forgets the state and the listeners. For tests,
  /// through `DartFirebaseAnalytics.debugReset`.
  void reset() {
    _listener?.dispose();
    _listener = null;
    _active = null;
    _listeners.clear();
  }
}

/// The binding, or null before `WidgetsFlutterBinding.ensureInitialized` (or
/// `runApp`) created it.
///
/// [WidgetsBinding.instance] has no form that answers null: before the binding
/// exists it throws (a [FlutterError] in debug builds, a null check failure in
/// release builds), so that is caught here.
WidgetsBinding? _bindingOrNull() {
  try {
    return WidgetsBinding.instance;
  } on Object {
    return null;
  }
}
