import 'package:flutter/material.dart';

import '../common/role_placeholder.dart';

/// The Area President's section. Owned by Charles Carcallas.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholder(
      title: 'Area President',
      owner: 'Charles Carcallas',
      firstScreens: <String>[
        'Post Bill Amount - read v_readings_awaiting_amount, post through '
            'PostBillAmount',
        'Accounts - create staff and consumer accounts for this area',
        'Disconnection notices - review v_active_disconnection_warnings',
      ],
    );
  }
}
