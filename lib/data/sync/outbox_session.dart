import '../../domain/entities/app_user.dart';

/// Identity captured with work, independent of the disposable cache owner.
final class OutboxScope {
  final String id;
  final String role;
  final String? area;
  const OutboxScope(this.id, this.role, this.area);
}

final class OutboxSession {
  OutboxScope? scope;
  int generation = 0;
  void bind(AppUser? user) {
    generation++;
    scope = user == null
        ? null
        : OutboxScope(user.id.value, user.roleCode, user.areaId?.value);
  }
}
