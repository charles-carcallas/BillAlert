import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/consumer.dart';
import '../../entities/household_login.dart';
import '../../value_objects/ids.dart';
import 'create_consumer.dart';
import 'create_household_login.dart';

/// What registering a household produced.
///
/// The household is the part that must exist. Its sign-in is created straight
/// after, and can fail on its own — most often a username someone already
/// has — without undoing the household, which can be given a sign-in later.
/// Exactly one of [login] and [loginFailure] is set.
final class RegisteredHousehold {
  final Consumer household;
  final CreatedHouseholdLogin? login;
  final AppFailure? loginFailure;

  const RegisteredHousehold({
    required this.household,
    this.login,
    this.loginFailure,
  });
}

/// ADM-03 + MTR-04 — the Area President registers a household, and it is
/// given its sign-in in the same step.
///
/// Two writes, not one transaction: the household row goes through the
/// client under row-level security, and the sign-in through an Edge Function
/// that holds the service-role key. So everything that can be checked is
/// checked before either is written, and a sign-in the server refuses leaves
/// the household saved and says why, rather than losing what was typed.
final class RegisterHousehold {
  final CreateConsumer createConsumer;
  final CreateHouseholdLogin createLogin;

  const RegisterHousehold({
    required this.createConsumer,
    required this.createLogin,
  });

  Future<Result<RegisteredHousehold>> call({
    required String consumerNo,
    required String firstName,
    required String lastName,
    required String contactNumber,
    required String purok,
    required String meterSerialNo,
    required String username,
    required AreaId areaId,
    required ProfileId createdBy,
  }) async {
    // A household saved with a username the server would refuse is a
    // household left without the sign-in this step promised.
    final ValidationFailure? invalid =
        CreateConsumer.check(
          consumerNo: consumerNo,
          firstName: firstName,
          lastName: lastName,
        ) ??
        CreateHouseholdLogin.checkUsername(username);
    if (invalid != null) return Err<RegisteredHousehold>(invalid);

    final Result<Consumer> saved = await createConsumer(
      consumerNo: consumerNo,
      firstName: firstName,
      lastName: lastName,
      contactNumber: contactNumber,
      purok: purok,
      meterSerialNo: meterSerialNo,
      areaId: areaId,
      createdBy: createdBy,
    );

    return switch (saved) {
      Err(:final failure) => Err<RegisteredHousehold>(failure),
      Ok(:final value) => Ok<RegisteredHousehold>(
        await _signIn(value, username),
      ),
    };
  }

  Future<RegisteredHousehold> _signIn(
    Consumer household,
    String username,
  ) async {
    final result = await createLogin(
      household: HouseholdWithoutLogin(
        id: household.id,
        consumerNo: household.consumerNo,
        firstName: household.firstName,
        lastName: household.lastName,
        purok: household.purok,
      ),
      username: username,
    );

    return switch (result) {
      Ok(:final value) => RegisteredHousehold(
        household: household,
        login: value,
      ),
      Err(:final failure) => RegisteredHousehold(
        household: household,
        loginFailure: failure,
      ),
    };
  }
}
