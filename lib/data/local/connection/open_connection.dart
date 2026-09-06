/// Opens the local database for whichever platform this build is for.
///
/// Android gets an encrypted SQLCipher file; the browser gets SQLite compiled
/// to WebAssembly, unencrypted. The conditional export is what lets one app
/// compile for both: `dart:io` and `package:path_provider` simply do not exist
/// on the web, and importing them unconditionally is what produced the wall of
/// "Dart library 'dart:ffi' is not available on this platform" errors.
///
/// Both files export the same two names:
///   QueryExecutor openBillAlertDatabase()
///   const bool databaseIsEncrypted
///
/// Read `web_connection.dart` before demoing a web build to anybody: the
/// second of those is false there, on purpose.
library;

export 'native_connection.dart'
    if (dart.library.js_interop) 'web_connection.dart';
