/// Headers of a request for the bytes of an object, on platforms with `dart:io`.
///
/// The `dart:io` client asks for gzip and unzips a gzip response by itself. For an object stored
/// gzip-compressed (`contentEncoding: gzip`) the server then sends the stored bytes, and reads a `Range` header
/// against them, while the client counts unzipped bytes: a ranged read would start in the middle of the gzip
/// data. Asking for the identity encoding makes the server unzip the object, so every offset is in unzipped
/// bytes; it then ignores the `Range` header and answers 200 with the whole object, which the download code
/// already handles.
const Map<String, String> mediaRequestHeaders = <String, String>{
  'Accept-Encoding': 'identity',
};
