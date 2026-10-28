import 'dart:async';
import 'package:billalert/data/network/foreground_poll.dart';
import 'package:billalert/data/network/network_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'offline stays quiet, reconnect refreshes once, pause stops polling',
    (tester) async {
      final links = StreamController<bool>.broadcast(sync: true);
      var link = false;
      final network = NetworkStatus(
        linkChanges: links.stream,
        checkLink: () async => link,
      );
      await tester.pump();
      var refreshes = 0;
      final poll = ForegroundPoll(network, () async {
        refreshes++;
      });
      poll.resume();
      await tester.pump(const Duration(minutes: 3));
      expect(refreshes, 0);
      link = true;
      links.add(true);
      await tester.pump();
      expect(refreshes, 1);
      links.add(true);
      await tester.pump();
      expect(refreshes, 1);
      poll.pause();
      await tester.pump(const Duration(minutes: 2));
      expect(refreshes, 1);
      poll.resume();
      await tester.pump();
      expect(refreshes, 2);
      network.reportUnreachable();
      var probes = 0;
      network.pingServer = () async {
        probes++;
      };
      await tester.pump(const Duration(minutes: 1));
      expect(probes, 1);
      expect(refreshes, 2);
      network.pingServer = () async {
        probes++;
        network.reportReachable();
      };
      await tester.pump(const Duration(minutes: 1));
      expect(
        refreshes,
        3,
        reason: 'Recovery listener and probe must not double refresh',
      );
      poll.dispose();
      network.dispose();
      await links.close();
    },
  );
}
