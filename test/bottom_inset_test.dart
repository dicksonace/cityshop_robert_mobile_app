import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cityshop_mobile/screens/account/account_screens.dart';

/// Height of a typical Android three-button navigation bar.
const _navBar = EdgeInsets.only(bottom: 48);

void main() {
  testWidgets('trailing action clears the system navigation bar', (tester) async {
    // Short viewport so the form has to scroll to reach the trailing button.
    tester.view.physicalSize = const Size(1080, 750);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewPadding: _navBar, padding: _navBar),
          child: child!,
        ),
        home: const ChangePasswordScreen(),
      ),
    );

    final button = find.text('Update password');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(screenHeight - _navBar.bottom));
  });
}
