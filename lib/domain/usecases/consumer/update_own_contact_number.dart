import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../repositories/consumer_repository.dart';

/// Lets a household change only the number that receives its SMS alerts.
///
/// Formatting deliberately remains server-owned: the existing contact trigger
/// accepts spaced Philippine numbers and stores E.164. This use case passes
/// the consumer's text through unchanged.
final class UpdateOwnContactNumber {
  final ConsumerRepository consumers;

  const UpdateOwnContactNumber({required this.consumers});

  Future<Result<String>> call({required String contactNumber}) {
    if (contactNumber.trim().isEmpty) {
      return Future<Result<String>>.value(
        const Err<String>(
          ValidationFailure(
            'Enter the mobile number that should receive SMS alerts.',
          ),
        ),
      );
    }
    return consumers.updateOwnContactNumber(contactNumber);
  }
}
