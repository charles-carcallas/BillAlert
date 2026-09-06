import '../../domain/entities/app_user.dart';
import '../../domain/value_objects/ids.dart';

/// Builds the right [AppUser] subclass from a `profiles` row.
///
/// This is the second and last place in the app that switches on a role
/// string, and for the same reason as OutboxCodec: something has to turn the
/// text in a column into an object. After this line every other part of the
/// app asks the user where it belongs instead of asking what role it has.
class ProfileDto {
  const ProfileDto._();

  static const String columns =
      'id, username, first_name, last_name, role, area_id, '
      'must_change_password, account_status';

  /// Returns null for a role this app version does not know, rather than
  /// guessing and dropping somebody into the wrong screen.
  static AppUser? fromJson(Map<String, dynamic> json) {
    final id = ProfileId(json['id'] as String);
    final username = json['username'] as String;
    final firstName = json['first_name'] as String;
    final lastName = json['last_name'] as String;
    final mustChangePassword = json['must_change_password'] as bool? ?? false;
    final areaValue = json['area_id'] as String?;
    final areaId = areaValue == null ? null : AreaId(areaValue);

    switch (json['role'] as String) {
      case 'admin':
        return AdminUser(
          id: id,
          username: username,
          firstName: firstName,
          lastName: lastName,
          areaId: areaId,
          mustChangePassword: mustChangePassword,
        );
      case 'meter_reader':
        return MeterReaderUser(
          id: id,
          username: username,
          firstName: firstName,
          lastName: lastName,
          areaId: areaId,
          mustChangePassword: mustChangePassword,
        );
      case 'cashier':
        return CashierUser(
          id: id,
          username: username,
          firstName: firstName,
          lastName: lastName,
          areaId: areaId,
          mustChangePassword: mustChangePassword,
        );
      case 'consumer':
        return ConsumerUser(
          id: id,
          username: username,
          firstName: firstName,
          lastName: lastName,
          mustChangePassword: mustChangePassword,
        );
      default:
        return null;
    }
  }
}
