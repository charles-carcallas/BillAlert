import 'dart:async';

import 'package:http/http.dart';

import 'network_status.dart';

/// The HTTP client every Supabase call goes through.
///
/// Every repository asks the server first and falls back to the phone's
/// cache only once that request fails. Left to itself a request on a dead
/// Wi-Fi link or a single bar of signal waits for the operating system to
/// give up, which can take a minute, and the screen spins all that time
/// before showing data it already had. So:
///
/// * with no network link at all, the request fails at once;
/// * with a link but a server that just failed to answer, it fails at once
///   too, apart from one probe every [NetworkStatus.probeInterval];
/// * otherwise the server has [timeout] to start answering, and a request
///   that runs out of time fails the same way a dropped connection does.
///
/// Both failures are the kind the repositories already treat as "offline",
/// so the cached data appears without any repository changing.
class FailFastHttpClient extends BaseClient {
  static const Duration defaultTimeout = Duration(seconds: 8);

  final Client _inner;
  final NetworkStatus _status;
  final Duration timeout;

  FailFastHttpClient(
    this._status, {
    Client? inner,
    this.timeout = defaultTimeout,
  }) : _inner = inner ?? Client();

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (!_status.hasLink) {
      throw ClientException('No network link on this phone.', request.url);
    }
    if (!_status.allowRequest()) {
      // The last attempt moments ago could not reach the server, so this one
      // would only wait out the same timeout. Fail now; the repositories
      // fall back to the phone's saved data.
      throw ClientException(
        'The server was unreachable a moment ago.',
        request.url,
      );
    }
    try {
      final StreamedResponse response = await _inner
          .send(request)
          .timeout(timeout);
      _status.reportReachable();
      return response;
    } on TimeoutException {
      _status.reportUnreachable();
      rethrow;
    } on ClientException {
      _status.reportUnreachable();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
