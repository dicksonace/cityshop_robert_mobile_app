import 'package:flutter_test/flutter_test.dart';

import 'package:cityshop_mobile/utils/chat_text_links.dart';

void main() {
  test('detects product links, store links, and Ghana phone numbers', () {
    const text =
        'Check out Toyota vite on CityShop — GH₵120,000.00\nhttps://cityunlock.net/products/toyota-vite call 0539790093';

    final segments = parseChatText(text);
    expect(segments.where((s) => s.kind == ChatTextKind.url).map((s) => s.text), [
      'https://cityunlock.net/products/toyota-vite',
    ]);
    expect(segments.where((s) => s.kind == ChatTextKind.phone).map((s) => s.text), [
      '0539790093',
    ]);

    final link = firstCityShopLinkIn(text);
    expect(link?.kind, 'product');
    expect(link?.slug, 'toyota-vite');
    expect(link?.inAppPath, '/products/toyota-vite');
  });

  test('app share links and web product links both open the product in-app', () {
    expect(
      parseCityShopDeepLink('https://cityunlock.net/app/products/honda-civic-2016')?.inAppPath,
      '/products/honda-civic-2016',
    );
    expect(
      parseCityShopDeepLink('https://cityunlock.net/products/honda-civic-2016')?.inAppPath,
      '/products/honda-civic-2016',
    );
    expect(
      parseCityShopDeepLink('https://cityunlock.net/app/store/city-unlock')?.inAppPath,
      '/stores/city-unlock',
    );
  });

  test('does not treat a price as a phone number', () {
    final segments = parseChatText('Total GH₵120,000.00 today');
    expect(segments.where((s) => s.kind == ChatTextKind.phone), isEmpty);
  });
}
