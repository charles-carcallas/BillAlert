import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/consumer.dart';
import '../../repositories/consumer_repository.dart';
import '../../value_objects/ids.dart';

/// ADM-03 — creates a household record in the Area President's own area.
///
/// This deliberately does not create an auth user. Provisioning an auth user
/// requires service-role credentials, and those credentials must never ship
/// in the client app.
final class CreateConsumer {
  final ConsumerRepository consumers;

  const CreateConsumer({required this.consumers});

  Future<Result<Consumer>> call({
    required String consumerNo,
    required String firstName,
    required String lastName,
    required String contactNumber,
    required String purok,
    required AreaId areaId,
    required ProfileId createdBy,
  }) {
    final String cleanConsumerNo = consumerNo.trim();
    final String cleanFirstName = firstName.trim();
    final String cleanLastName = lastName.trim();

    if (cleanConsumerNo.isEmpty) {
      return Future<Result<Consumer>>.value(
        const Err<Consumer>(
          ValidationFailure(
            'Enter the consumer number from the household record.',
          ),
        ),
      );
    }
    if (cleanFirstName.isEmpty) {
      return Future<Result<Consumer>>.value(
        const Err<Consumer>(
          ValidationFailure('Enter the consumer\'s first name.'),
        ),
      );
    }
    if (cleanLastName.isEmpty) {
      return Future<Result<Consumer>>.value(
        const Err<Consumer>(
          ValidationFailure('Enter the consumer\'s last name.'),
        ),
      );
    }

    return consumers.create(
      consumerNo: ConsumerNumber(cleanConsumerNo),
      firstName: cleanFirstName,
      lastName: cleanLastName,
      areaId: areaId,
      createdBy: createdBy,
      // A blank optional value is absence. A real mobile number is preserved
      // exactly as typed; the database trigger owns its normalisation.
      contactNumber: contactNumber.trim().isEmpty ? null : contactNumber,
      purok: purok.trim().isEmpty ? null : purok.trim(),
    );
  }
}
