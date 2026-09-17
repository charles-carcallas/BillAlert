import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/data/network/fail_fast_http_client.dart';
import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/supabase/failure_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

void main() {
  late StreamController<bool> link;
  late NetworkStatus status;
  late DateTime now;

  setUp(() async {
    link = StreamController<bool>();
    now = DateTime.utc(2026, 9, 17, 8);
    status = NetworkStatus(
      linkChanges: link.stream,
      checkLink: () async => true,
      clock: () => now,
    );
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    status.dispose();
    await link.close();
  });

  final Uri url = Uri.parse('https://example.supabase.co/rest/v1/bills');

  test(
    'with no network link, a request fails at once without being sent',
    () async {
      var sent = 0;
      final client = FailFastHttpClient(
        status,
        inner: MockClient((_) async {
          sent++;
          return Response('[]', 200);
        }),
      );
      link.add(false);
      await Future<void>.delayed(Duration.zero);

      final Stopwatch clock = Stopwatch()..start();
      final Object error = await client
          .get(url)
          .then<Object>((_) => 'no error', onError: (Object e) => e);

      expect(sent, 0);
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 200)));
      // The repositories already fall back to the cache for exactly this.
      expect(
        FailureMapper.from(error, StackTrace.empty),
        isA<NetworkFailure>(),
      );
      expect(status.isOnline, isFalse);
    },
  );

  test('a server that never answers gives up after the timeout', () async {
    final client = FailFastHttpClient(
      status,
      timeout: const Duration(milliseconds: 50),
      inner: MockClient((_) => Completer<Response>().future),
    );

    final Object error = await client
        .get(url)
        .then<Object>((_) => 'no error', onError: (Object e) => e);

    expect(error, isA<TimeoutException>());
    expect(FailureMapper.from(error, StackTrace.empty), isA<NetworkFailure>());
    expect(status.isOnline, isFalse);
  });

  test(
    'the next request that gets through marks the app online again',
    () async {
      var fail = true;
      final client = FailFastHttpClient(
        status,
        inner: MockClient((_) async {
          if (fail) throw ClientException('Connection reset', url);
          return Response('[]', 200);
        }),
      );

      await expectLater(client.get(url), throwsA(isA<ClientException>()));
      expect(status.isOnline, isFalse);

      fail = false;
      // The next probe is allowed once the interval has passed.
      now = now.add(status.probeInterval);
      await client.get(url);
      expect(status.isOnline, isTrue);
    },
  );

  test('a new network link clears an earlier unreachable report', () async {
    status.reportUnreachable();
    expect(status.isOnline, isFalse);

    link.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(status.isOnline, isTrue);
  });

  test('after a failed request, the next ones fail at once without being '
      'sent', () async {
    var sent = 0;
    final client = FailFastHttpClient(
      status,
      timeout: const Duration(milliseconds: 50),
      inner: MockClient((_) {
        sent++;
        return Completer<Response>().future;
      }),
    );

    await expectLater(client.get(url), throwsA(isA<TimeoutException>()));
    expect(sent, 1);

    final Stopwatch clock = Stopwatch()..start();
    await expectLater(client.get(url), throwsA(isA<ClientException>()));
    await expectLater(client.get(url), throwsA(isA<ClientException>()));

    expect(sent, 1);
    expect(clock.elapsed, lessThan(const Duration(milliseconds: 40)));
  });

  test('one probe is let through every interval while unreachable', () async {
    var sent = 0;
    final client = FailFastHttpClient(
      status,
      inner: MockClient((_) async {
        sent++;
        throw ClientException('No route to host', url);
      }),
    );

    await expectLater(client.get(url), throwsA(isA<ClientException>()));
    now = now.add(const Duration(seconds: 5));
    await expectLater(client.get(url), throwsA(isA<ClientException>()));
    expect(sent, 1);

    now = now.add(status.probeInterval);
    await expectLater(client.get(url), throwsA(isA<ClientException>()));
    expect(sent, 2);
  });

  test('Retry pings the server at once and clears the offline state when it '
      'answers', () async {
    var up = false;
    final client = FailFastHttpClient(
      status,
      inner: MockClient((_) async {
        if (!up) throw ClientException('No route to host', url);
        return Response('', 401);
      }),
    );
    status.pingServer = () async {
      try {
        await client.head(url);
      } catch (_) {}
    };

    await expectLater(client.get(url), throwsA(isA<ClientException>()));
    expect(status.isOnline, isFalse);

    up = true;
    await status.recheck();

    // Any HTTP answer, even a refusal, proves the server is reachable.
    expect(status.isOnline, isTrue);
  });
}
