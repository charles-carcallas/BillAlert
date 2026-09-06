import 'package:flutter/material.dart';

import '../common/role_placeholder.dart';

/// The Cashier's section. Owned by Obiso.
class CashierHomeScreen extends StatelessWidget {
  const CashierHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RolePlaceholder(
      title: 'Cashier',
      owner: 'Obiso',
      firstScreens: <String>[
        'Collect payment - one handover, one receipt, through '
            'RecordCashPayment',
        'Consumer lookup - read v_cashier_collection_progress',
        'Daily summary - read v_cashier_daily_summary',
      ],
    );
  }
}
