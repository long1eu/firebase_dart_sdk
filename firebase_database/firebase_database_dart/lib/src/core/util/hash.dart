/// SHA-1 and string-size helpers. JS: `core/util/util.ts` (`sha1`, `splitStringBySize`) and
/// `@firebase/util` `stringLength`; Android: `core/utilities/Utilities.java` (`sha1HexDigest`,
/// `stringHashV2Representation`).
library;

/// The base64 of the SHA-1 digest of the UTF-8 bytes of [text], as node hashes use it.
String sha1Base64(String text) => throw UnimplementedError();

/// The number of UTF-8 bytes of [text].
int utf8Length(String text) => throw UnimplementedError();

/// Splits [text] into pieces of at most [segmentSize] UTF-16 code units.
List<String> splitStringBySize(String text, int segmentSize) => throw UnimplementedError();

/// [text] in the V2 hash form of the compound hash: JSON-quoted with only `\` and `"` escaped.
String stringHashV2Representation(String text) => throw UnimplementedError();
