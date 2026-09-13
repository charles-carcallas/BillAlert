import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/staff_app_bar.dart';
import '../router.dart';
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
                        'Create staff and consumer accounts here. Editing '
                        'existing accounts is deferred.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      // A forgotten password was a dead end: the sign-in
                      // screen told people to ask their Area President, who
                      // had no way to help.
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push(Routes.resetAccountPassword),
                        icon: const Icon(Icons.lock_reset_outlined, size: 18),
                        label: const Text('Reset a forgotten password'),
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
