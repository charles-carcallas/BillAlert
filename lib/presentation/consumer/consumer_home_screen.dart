import 'package:flutter/material.dart';

import '../common/role_placeholder.dart';

/// The household's section. Owned by Basio.
class ConsumerHomeScreen extends StatelessWidget {
  const ConsumerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholder(
      title: 'My Bill',
      owner: 'Basio',
      firstScreens: <String>[
        'Current bill - read v_consumer_current_bill, which INCLUDES '
            'unpriced bills',
        'History - read v_payment_history',
        'Alerts - read cached_notifications, readable offline',
      ],
    );
  }
}
