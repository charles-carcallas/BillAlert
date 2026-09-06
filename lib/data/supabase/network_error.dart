/// "Was this failure the network, or something else?"
///
/// The answer differs by platform. On a phone a dead connection surfaces as a
/// `SocketException` from `dart:io`; in a browser there is no such class, and
/// a failed request arrives as a `ClientException` instead. Importing
/// `dart:io` unconditionally is what stops an app compiling for the web at
/// all, so the platform-specific half lives behind this conditional export
/// and nothing else in the app has to care.
library;

export 'network_error_io.dart'
    if (dart.library.js_interop) 'network_error_web.dart';
