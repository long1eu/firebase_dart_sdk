import 'package:firebase_remote_config_dart/src/platform.dart';
import 'package:web/web.dart' as web;

/// The language of the browser: `navigator.language`, reduced to a BCP 47 tag.
String defaultLanguage() => normalizeLanguageTag(web.window.navigator.language);

/// A [Visibility] over `document.visibilityState` and the `visibilitychange` event.
Visibility createVisibility() => const _PageVisibility();

final class _PageVisibility implements Visibility {
  const _PageVisibility();

  @override
  bool get isHidden => web.document.visibilityState == 'hidden';

  @override
  Stream<bool> get changes => const web.EventStreamProvider<web.Event>(
    'visibilitychange',
  ).forTarget(web.document).map((web.Event _) => isHidden);
}
