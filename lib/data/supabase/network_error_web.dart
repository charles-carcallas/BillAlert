import 'dart:async';

import 'package:http/http.dart' show ClientException;

/// The browser. `dart:io` does not exist here, so there is no SocketException
/// to catch; a request that fails to reach the server throws a
/// ClientException from package:http instead.
bool isNetworkError(Object error) =>
    error is TimeoutException || error is ClientException;
