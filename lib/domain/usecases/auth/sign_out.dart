import '../../../core/result/result.dart';
import '../../repositories/auth_repository.dart';

/// GEN-06 - signing out, which also wipes the cached data on this phone.
///
/// The outbox is deliberately not cleared: signing out with unsynced field
/// work would throw a morning of readings away. The screen warns and asks
/// before that can happen.
final class SignOut {
  final AuthRepository auth;

  const SignOut({required this.auth});

  Future<Result<void>> call() => auth.signOut();
}
