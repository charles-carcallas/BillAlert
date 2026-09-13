import 'package:flutter/material.dart';

import '../common/staff_app_bar.dart';
import 'account_form_widgets.dart';
import 'new_consumer_screen.dart';
import 'new_staff_screen.dart';

/// Admin › Accounts, following Figma's unified "New account" workspace.
///
/// Both creation flows remain separate widgets with their own controllers.
/// This screen only switches which form is visible; it never combines their
/// data or bypasses either flow's validation and final confirmation.
class AdminAccountsScreen extends StatefulWidget {
  const AdminAccountsScreen({super.key});

  @override
  State<AdminAccountsScreen> createState() => _AdminAccountsScreenState();
}

class _AdminAccountsScreenState extends State<AdminAccountsScreen> {
  bool _staffSelected = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StaffAppBar(title: 'New account'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Create staff and consumer accounts here. Listing '
                        'and editing existing accounts is deferred.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      AdminAccountTypeSelector(
                        staffSelected: _staffSelected,
                        onStaffSelected: (bool value) {
                          if (_staffSelected != value) {
                            setState(() => _staffSelected = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _staffSelected ? 0 : 1,
                children: const <Widget>[
                  AdminNewStaffScreen(embedded: true, showIntro: false),
                  AdminNewConsumerScreen(embedded: true, showIntro: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
