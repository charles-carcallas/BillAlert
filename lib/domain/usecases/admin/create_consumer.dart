import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/consumer.dart';
import '../../repositories/consumer_repository.dart';
import '../../value_objects/ids.dart';

/// ADM-03 — creates a household record in the Area President's own area.
///
/// This deliberately does not create an auth user. Provisioning an auth user
/// requires service-role credentials, and those credentials must never ship
/// in the client app. `RegisterHousehold` follows this with MTR-04's
/// `CreateHouseholdLogin`, which does it through a server-side Edge Function.
final class CreateConsumer {
  final ConsumerRepository consumers;

  const CreateConsumer({required this.consumers});

  /// Offline nothing is saved, and nothing is kept to try later: the server
  /// has to check the consumer, meter and mobile numbers are not already used.
  static const String needsSignal =
      'Adding a household needs signal. Nothing was saved. Try again when '
      "you're back online.";

  /// The first thing wrong with these household details, in the order the
  /// form asks for them, or null when there is nothing.
  static ValidationFailure? check({
    required String consumerNo,
    required String firstName,
    required String lastName,
  }) {
    if (consumerNo.trim().isEmpty) {
      return const ValidationFailure(
        'Enter the consumer number from the household record.',
      );
    }
    if (firstName.trim().isEmpty) {
      return const ValidationFailure('Enter the consumer\'s first name.');
    }
    if (lastName.trim().isEmpty) {
      return const ValidationFailure('Enter the consumer\'s last name.');
    }
    return null;
  }

  Future<Result<Consumer>> call({
    required String consumerNo,
    required String firstName,
    required String lastName,
    required String contactNumber,
    required String purok,
    required String meterSerialNo,
    required AreaId areaId,
    required ProfileId createdBy,
  }) {
    final ValidationFailure? invalid = check(
      consumerNo: consumerNo,
      firstName: firstName,
      lastName: lastName,
    );
    if (invalid != null) {
      return Future<Result<Consumer>>.value(Err<Consumer>(invalid));
    }

    // "biec-08317" and "BIEC-08317" are the same meter. The database's unique
    // index compares them exactly, so one spelling is chosen here.
    final String cleanMeterSerialNo = meterSerialNo.trim().toUpperCase();

    return consumers
        .create(
          consumerNo: ConsumerNumber(consumerNo.trim()),
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          areaId: areaId,
          createdBy: createdBy,
          // A blank optional value is absence. A real mobile number is preserved
          // exactly as typed; the database trigger owns its normalisation.
          contactNumber: contactNumber.trim().isEmpty ? null : contactNumber,
          purok: purok.trim().isEmpty ? null : purok.trim(),
          // Optional: a household can be registered before its meter is
          // commissioned, and the number added then.
          meterSerialNo: cleanMeterSerialNo.isEmpty ? null : cleanMeterSerialNo,
        )
        .then((result) => result.ifOffline(needsSignal));
  }
}
