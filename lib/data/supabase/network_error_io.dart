import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;

/// Android, iOS, Windows, macOS, Linux.
bool isNetworkError(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is TimeoutException ||
    error is ClientException;
