import 'package:firebase_auth_secure_storage_dart/src/linux/libsecret_bindings.dart';
import 'package:firebase_auth_secure_storage_dart/src/secret_store.dart';

/// A [SecretStore] in the Secret Service of Linux (GNOME Keyring, KDE
/// Wallet, KeePassXC), through libsecret.
///
/// Each secret is an item of the default collection (`login`) with the
/// schema [service] and the string attributes `service` = [service] and
/// `account` = the account name; its label is `<service> <account>`, which
/// is what a keyring manager such as Seahorse shows.
///
/// libsecret (`libsecret-1.so.0`) is loaded at the first call; a system
/// without it fails that call with a [SecretStoreError] for `dlopen`. The
/// calls are the synchronous ones of libsecret: they block the isolate while
/// the Secret Service answers over D-Bus. Without a D-Bus session bus or a
/// Secret Service on it, they fail with a `GError` of the D-Bus or GIO
/// domain; with a locked collection and no prompter they fail with
/// `secret-error` code 2 (`SECRET_ERROR_IS_LOCKED`) or wait for the prompt.
class LibsecretSecretStore implements SecretStore {
  /// A store for the items of [service].
  LibsecretSecretStore({required this.service});

  /// The schema name and the `service` attribute of the items.
  final String service;

  LibsecretBindings? _bindings;

  LibsecretBindings get _api => _bindings ??= LibsecretBindings.load(service);

  @override
  Future<String?> read(String account) =>
      Future<String?>(() => _api.lookup(service, account));

  @override
  Future<void> write(String account, String secret) => Future<void>(
    () => _api.store(service, account, '$service $account', secret),
  );

  @override
  Future<void> delete(String account) =>
      Future<void>(() => _api.clear(service, account));
}
