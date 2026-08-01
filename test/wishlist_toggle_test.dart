import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/store/app_store.dart';

/// Holds `/wishlist/toggle` open so the pre-response state can be inspected.
class _PendingApiClient extends ApiClient {
  final _pending = Completer<Response<dynamic>>();
  int posts = 0;

  void answer({required bool wishlisted}) => _pending.complete(
        Response(
          requestOptions: RequestOptions(path: '/wishlist/toggle'),
          data: {'wishlisted': wishlisted},
        ),
      );

  void fail() => _pending.completeError(ApiException('offline'));

  @override
  Future<Response<dynamic>> post(String path, {Object? data}) {
    posts++;
    return _pending.future;
  }
}

void main() {
  test('heart flips before the server answers', () async {
    final api = _PendingApiClient();
    final store = AppStore(api);
    var notifications = 0;
    store.addListener(() => notifications++);

    final pending = store.toggleWishlist(7);
    await Future<void>.delayed(Duration.zero);

    expect(store.wishlistProductIds, contains(7));
    expect(notifications, greaterThan(0));
    expect(api.posts, 1);

    api.answer(wishlisted: true);
    expect(await pending, isTrue);
    expect(store.wishlistProductIds, contains(7));
  });

  test('a failed request puts the heart back', () async {
    final api = _PendingApiClient();
    final store = AppStore(api);

    final pending = store.toggleWishlist(7);
    await Future<void>.delayed(Duration.zero);
    expect(store.wishlistProductIds, contains(7));

    api.fail();

    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(store.wishlistProductIds, isNot(contains(7)));
  });

  test('the server wins when it disagrees with the optimistic flip', () async {
    final api = _PendingApiClient();
    final store = AppStore(api);

    final pending = store.toggleWishlist(7);
    await Future<void>.delayed(Duration.zero);
    expect(store.wishlistProductIds, contains(7));

    // The product was already wishlisted server-side, so the toggle removed it.
    api.answer(wishlisted: false);

    expect(await pending, isFalse);
    expect(store.wishlistProductIds, isNot(contains(7)));
  });
}
