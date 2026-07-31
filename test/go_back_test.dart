import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cityshop_mobile/widgets/common_widgets.dart';

const _fallback = '/shop?tab=orders';

Widget _page(String label) => Scaffold(
      appBar: AppBar(
        title: TextButton(
          onPressed: () => goBackOr(_key.currentContext!, _fallback),
          child: const Text('Back'),
        ),
      ),
      body: Center(child: Text(label)),
    );

final _key = GlobalKey();

GoRouter _router(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/orders', builder: (_, __) => _page('orders list')),
        GoRoute(
          path: '/orders/1',
          builder: (context, __) => KeyedSubtree(key: _key, child: _page('order detail')),
        ),
        GoRoute(path: '/shop', builder: (_, __) => _page('shop shell')),
      ],
    );

void main() {
  testWidgets('back pops to the previous page when one exists', (tester) async {
    final router = _router('/orders');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push('/orders/1');
    await tester.pumpAndSettle();
    expect(find.text('order detail'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('orders list'), findsOneWidget);
  });

  testWidgets('back falls through to purchases when the stack is empty', (tester) async {
    // `go` replaces the stack, which is how checkout hands off to order detail.
    final router = _router('/orders/1');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('order detail'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('shop shell'), findsOneWidget);
  });
}
