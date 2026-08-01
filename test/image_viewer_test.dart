import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cityshop_mobile/widgets/image_viewer.dart';

const _urls = [
  'https://cityunlock.net/storage/products/one.jpg',
  'https://cityunlock.net/storage/products/two.jpg',
  'https://cityunlock.net/storage/products/three.jpg',
];

/// The loading spinner animates forever, so pumpAndSettle would never return.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openViewer(WidgetTester tester, {int initialIndex = 0}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showImageViewer(context, urls: _urls, initialIndex: initialIndex),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await _pumpFrames(tester);
}

void main() {
  testWidgets('opens on the tapped photo', (tester) async {
    await _openViewer(tester, initialIndex: 1);

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('steps through photos and closes', (tester) async {
    await _openViewer(tester);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await _pumpFrames(tester);
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await _pumpFrames(tester);

    expect(find.text('2 / 3'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('double tap zooms and blocks page swiping', (tester) async {
    await _openViewer(tester);

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_in));
    await _pumpFrames(tester);

    // Zooming swaps the icon and hides the pager arrows so panning wins.
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('an empty gallery does not open the viewer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showImageViewer(context, urls: const []),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await _pumpFrames(tester);

    expect(find.byType(ImageViewer), findsNothing);
  });
}
