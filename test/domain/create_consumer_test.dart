import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/usecases/admin/create_consumer.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  const AreaId area3 = AreaId('area-3');
  const ProfileId admin = ProfileId('admin-1');

  late FakeConsumerRepository consumers;
  late CreateConsumer createConsumer;

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[]);
    createConsumer = CreateConsumer(consumers: consumers);
  });

  Future<Result<Consumer>> create({
    String consumerNo = '2026-1234-TUB',
    String firstName = 'Lorna',
    String lastName = 'Caberte',
    String contactNumber = '0917 555 0142',
    String purok = 'Purok 4',
    String meterSerialNo = 'BIEC-08399',
  }) => createConsumer(
    consumerNo: consumerNo,
    firstName: firstName,
    lastName: lastName,
    contactNumber: contactNumber,
    purok: purok,
    meterSerialNo: meterSerialNo,
    areaId: area3,
    createdBy: admin,
  );

  test(
    'consumer number is required because the database has no generator',
    () async {
      final result = await create(consumerNo: '   ');

      expect(result, isA<Err<Consumer>>());
      expect((result as Err<Consumer>).failure, isA<ValidationFailure>());
      expect(consumers.createCount, 0);
    },
  );

  test('first and last names are required separately', () async {
    final missingFirst = await create(firstName: '');
    final missingLast = await create(lastName: '');

    expect((missingFirst as Err<Consumer>).failure, isA<ValidationFailure>());
    expect((missingLast as Err<Consumer>).failure, isA<ValidationFailure>());
    expect(consumers.createCount, 0);
  });

  test(
    'mobile text reaches the repository without client normalisation',
    () async {
      const typed = '0917 555 0142';

      final result = await create(contactNumber: typed);

      expect(result, isA<Ok<Consumer>>());
      expect(consumers.createdContactNumber, typed);
      expect(consumers.createdAreaId, area3);
      expect(consumers.createdBy, admin);
    },
  );

  test('the meter number is kept, in one spelling', () async {
    await create(meterSerialNo: ' biec-08399 ');

    expect(consumers.createdMeterSerialNo, 'BIEC-08399');
  });

  test('a household without a meter number can still be created', () async {
    final result = await create(meterSerialNo: '');

    expect(result, isA<Ok<Consumer>>());
    expect(consumers.createdMeterSerialNo, isNull);
  });

  test('blank optional fields become absent', () async {
    await create(contactNumber: '  ', purok: '  ', meterSerialNo: '  ');

    expect(consumers.createdContactNumber, isNull);
    expect(consumers.createdPurok, isNull);
    expect(consumers.createdMeterSerialNo, isNull);
  });
}
