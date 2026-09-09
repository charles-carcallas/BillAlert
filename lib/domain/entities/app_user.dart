import '../value_objects/ids.dart';

/// An icon slot, named rather than drawn. The domain layer cannot import
/// Flutter, so it names the icon and `presentation/` decides what it looks
/// like.
enum NavIcon {
  readings,
  consumers,
  amounts,
  disconnections,
  accounts,
  payment,
  receipts,
  bill,
  history,
  inbox,
  profile,
}

/// One destination in a role's bottom navigation.
final class AppTab {
  final String label;
  final String route;
  final NavIcon icon;

  const AppTab({required this.label, required this.route, required this.icon});
}

/// A signed-in user, in one of BillAlert's four roles.
///
/// This is the one place in the app where inheritance earns its keep. Every
/// role goes to a different home screen and sees a different set of tabs, and
/// role routing is asked for in half a dozen places. Written as a `switch` on
/// a role string, that decision gets copied into every one of them and they
/// drift apart. Written as [homeRoute] and [permittedTabs] on a sealed class,
/// the router just asks the user where they belong — and adding a fifth role
/// makes the compiler list every place that must change.
sealed class AppUser {
  final ProfileId id;
  final String username;
  final String firstName;
  final String lastName;

  /// Which of the four service areas of Tubod. Null for a consumer, who is
  /// not staff and is not area-scoped.
  final AreaId? areaId;

  /// GEN-04: a new account gets a temporary password and must change it
  /// before it can reach anything else.
  final bool mustChangePassword;

  const AppUser({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.areaId,
    required this.mustChangePassword,
  });

  String get fullName => '$firstName $lastName';

  /// Where the router sends this user after sign-in.
  String get homeRoute;

  /// What the bottom navigation offers. The first entry is [homeRoute].
  List<AppTab> get permittedTabs;

  /// The value in `profiles.role`.
  String get roleCode;

  /// What the profile screen calls this role.
  String get roleLabel;
}

/// The Area President. Scoped to one service area — an Admin here is not a
/// superuser, and Row-Level Security enforces that server-side.
final class AdminUser extends AppUser {
  const AdminUser({
    required super.id,
    required super.username,
    required super.firstName,
    required super.lastName,
    required super.areaId,
    required super.mustChangePassword,
  });

  @override
  String get homeRoute => '/admin';

  @override
  String get roleCode => 'admin';

  @override
  String get roleLabel => 'Area President';

  /// The four Admin tabs of the mockup. Posting amounts is first because it
  /// is the job that has a queue waiting on it.
  @override
  List<AppTab> get permittedTabs => const <AppTab>[
        AppTab(label: 'Amounts', route: '/admin', icon: NavIcon.amounts),
        AppTab(
          label: 'Notices',
          route: '/admin/disconnections',
          icon: NavIcon.disconnections,
        ),
        AppTab(label: 'Accounts', route: '/admin/accounts', icon: NavIcon.accounts),
        AppTab(label: 'Profile', route: '/admin/profile', icon: NavIcon.profile),
      ];
}

/// Walks the area and records readings, usually with no signal.
final class MeterReaderUser extends AppUser {
  const MeterReaderUser({
    required super.id,
    required super.username,
    required super.firstName,
    required super.lastName,
    required super.areaId,
    required super.mustChangePassword,
  });

  @override
  String get homeRoute => '/reader';

  @override
  String get roleCode => 'meter_reader';

  @override
  String get roleLabel => 'Meter Reader';

  @override
  List<AppTab> get permittedTabs => const <AppTab>[
        AppTab(label: 'Readings', route: '/reader', icon: NavIcon.readings),
        AppTab(
          label: 'Consumers',
          route: '/reader/consumers',
          icon: NavIcon.consumers,
        ),
        AppTab(label: 'Profile', route: '/reader/profile', icon: NavIcon.profile),
      ];
}

/// Takes cash at the counter and issues one receipt per handover.
final class CashierUser extends AppUser {
  const CashierUser({
    required super.id,
    required super.username,
    required super.firstName,
    required super.lastName,
    required super.areaId,
    required super.mustChangePassword,
  });

  @override
  String get homeRoute => '/cashier';

  @override
  String get roleCode => 'cashier';

  @override
  String get roleLabel => 'Cashier';

  /// Consumers comes first because a payment starts by finding the household
  /// standing at the counter; the payment screen is reached from there.
  @override
  List<AppTab> get permittedTabs => const <AppTab>[
        AppTab(label: 'Consumers', route: '/cashier', icon: NavIcon.consumers),
        AppTab(label: 'Payment', route: '/cashier/payment', icon: NavIcon.payment),
        AppTab(
          label: 'Receipts',
          route: '/cashier/receipts',
          icon: NavIcon.receipts,
        ),
        AppTab(label: 'Profile', route: '/cashier/profile', icon: NavIcon.profile),
      ];
}

/// The household. Sees their own bill, history, receipts and alerts.
final class ConsumerUser extends AppUser {
  const ConsumerUser({
    required super.id,
    required super.username,
    required super.firstName,
    required super.lastName,
    required super.mustChangePassword,
  }) : super(areaId: null);

  @override
  String get homeRoute => '/consumer';

  @override
  String get roleCode => 'consumer';

  @override
  String get roleLabel => 'Consumer';

  @override
  List<AppTab> get permittedTabs => const <AppTab>[
        AppTab(label: 'Bill', route: '/consumer', icon: NavIcon.bill),
        AppTab(label: 'History', route: '/consumer/history', icon: NavIcon.history),
        AppTab(label: 'Inbox', route: '/consumer/inbox', icon: NavIcon.inbox),
        AppTab(label: 'Profile', route: '/consumer/profile', icon: NavIcon.profile),
      ];
}
