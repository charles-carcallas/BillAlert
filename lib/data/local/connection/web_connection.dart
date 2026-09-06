import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// The browser. For development and demos only — read the warning below.
///
/// The database is SQLite compiled to WebAssembly, stored by the browser in
/// OPFS or IndexedDB depending on what it supports. Two files have to be
/// served alongside the app, and both are committed under `web/`:
///
///   web/sqlite3.wasm      SQLite itself
///   web/drift_worker.js   drift's worker, copied from the drift package so
///                         that it always matches the installed version
///
/// THE CACHE IS NOT ENCRYPTED ON THE WEB, and it cannot honestly be made so.
///
/// SYS-05 is satisfied on Android by SQLCipher plus a key in the Android
/// Keystore. Neither half survives the move to a browser:
///
///  1. drift opens the database inside a web worker whenever the browser
///     supports one, and its `localSetup` callback — the only place a
///     `PRAGMA key` could run — is documented as *not* being called in that
///     case. Keying it would mean compiling and maintaining a custom drift
///     worker, and a build step that silently loses encryption when somebody
///     forgets it is worse than no encryption at all.
///  2. Even then, the key would live in browser storage, readable by any
///     script on the origin and by anyone with the developer tools open. It
///     would look like protection without being any.
///
/// So: do not sign in as a real consumer here, and do not demo this build as
/// evidence that the cache is encrypted. Use an Android device for that. The
/// meter reader in Tubod is on a phone with no signal, which is a place a
/// browser cannot go anyway.
QueryExecutor openBillAlertDatabase() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'billalert_cache',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );

    if (result.missingFeatures.isNotEmpty) {
      // Not fatal: drift falls back to a less durable storage implementation.
      // Worth knowing about, because "my readings vanished" on the web is
      // usually this.
      // ignore: avoid_print
      print(
        'BillAlert (web): using ${result.chosenImplementation}. '
        'This browser is missing ${result.missingFeatures}, so queued work '
        'may not survive a refresh. Android is the supported platform.',
      );
    }

    return result.resolvedExecutor;
  });
}

/// False, and the app says so out loud rather than quietly implying SYS-05.
const bool databaseIsEncrypted = false;
