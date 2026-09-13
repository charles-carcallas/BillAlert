import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/usecases/consumer/update_own_contact_number.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeConsumerRepository consumers;
  late UpdateOwnContactNumber update;

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[]);
    update = UpdateOwnContactNumber(consumers: consumers);
  });

  test(
    'passes spaced mobile text through without client normalization',
    () async {
      const String typed = '0917 555 0142';

      final result = await update(contactNumber: typed);

      expect(result, isA<Ok<String>>());
      expect(consumers.updatedContactText, typed);
      expect(consumers.updateContactCount, 1);
    },
  );

  test('refuses a blank SMS number before calling the repository', () async {
    final result = await update(contactNumber: '   ');

    expect(result, isA<Err<String>>());
    expect((result as Err<String>).failure, isA<ValidationFailure>());
    expect(consumers.updateContactCount, 0);
  });
}
