/// Headers of a request for the bytes of an object, on the web: none. Browsers do not let a page set
/// `Accept-Encoding`, and they unzip a response before the page sees its bytes.
const Map<String, String> mediaRequestHeaders = <String, String>{};
