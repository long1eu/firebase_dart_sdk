// The few DOM members the in-page reCAPTCHA presenter uses, as dart:js_interop extension types, so
// that the package needs no dependency. Web builds only; not exported.

import 'dart:js_interop';

/// `window.document`.
@JS('document')
external Document get document;

/// `window.matchMedia(query).matches`.
bool mediaMatches(String query) => _matchMedia(query).matches;

@JS('matchMedia')
external _MediaQueryList _matchMedia(String query);

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

/// A DOM `Event`.
extension type Event._(JSObject _) implements JSObject {}

/// A DOM `Node` with the members used here.
extension type Node._(JSObject _) implements JSObject {
  /// Adds [child] as the last child.
  external Node appendChild(Node child);

  /// Whether the node is in a document.
  external bool get isConnected;
}

/// The `document`.
extension type Document._(JSObject _) implements Node {
  /// `<html>`.
  external Element? get documentElement;

  /// `<head>`.
  external Element? get head;

  /// `<body>`.
  external Element? get body;

  /// A new element of [tagName].
  external Element createElement(String tagName);

  /// The element whose id is [id], or null.
  external Element? getElementById(String id);
}

/// A DOM `Element`.
extension type Element._(JSObject _) implements Node {
  /// The element's id.
  external String get id;
  external set id(String value);

  /// The parent element, or null.
  external Element? get parentElement;

  /// The number of child elements.
  external int get childElementCount;

  /// Removes the element from its parent.
  external void remove();
}

/// A `<div>`.
extension type HTMLDivElement._(Element _) implements Element {
  /// A new `<div>`.
  HTMLDivElement() : _ = document.createElement('div');
}

/// A `<script>`.
extension type HTMLScriptElement._(Element _) implements Element {
  /// A new `<script>`.
  HTMLScriptElement() : _ = document.createElement('script');

  /// The address of the script.
  external set src(String value);

  /// Whether it runs as soon as it loaded.
  external set async(bool value);

  /// Called when the script loaded.
  external set onload(JSFunction? value);

  /// Called when the script failed to load.
  external set onerror(JSFunction? value);
}
