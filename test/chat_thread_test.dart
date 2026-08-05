import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:cityshop_mobile/api/api_client.dart';
import 'package:cityshop_mobile/models/models.dart';
import 'package:cityshop_mobile/screens/chat/messages_screens.dart';
import 'package:cityshop_mobile/store/app_store.dart';

Map<String, dynamic> _message(
  int id, {
  required String type,
  String body = '',
  int senderId = 9,
  String? imageUrl,
  Map<String, dynamic>? callLog,
}) =>
    {
      'id': id,
      'sender_id': senderId,
      'type': type,
      'body': body,
      'metadata': {
        if (imageUrl != null) 'image_url': imageUrl,
        if (callLog != null) 'call_log': callLog,
      },
      'created_at': '2026-08-01T18:23:00+00:00',
      'is_deleted': false,
      'can_delete': false,
    };

/// The thread Robert saw: a call, its signalling rows, a photo and one text.
final _thread = <Map<String, dynamic>>[
  _message(1, type: 'text', body: 'Do you have the iPhone 12 in stock?', senderId: 1),
  _message(2, type: 'call_offer', body: 'Voice call'),
  _message(3, type: 'call_ice'),
  _message(4, type: 'call_answer'),
  _message(5, type: 'call_ice'),
  _message(6, type: 'call_end'),
  _message(7, type: 'call_log', body: 'Voice call', callLog: {
    'status': 'ended',
    'duration_seconds': 65,
  }),
  _message(8, type: 'image', imageUrl: 'https://cdn.example.com/chat/phone.jpg', body: 'Here it is'),
];

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.product, List<Map<String, dynamic>>? messages})
      : messages = messages ?? _thread;

  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> messages;
  final uploads = <Map<String, dynamic>>[];

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final data = path == '/messages/7'
        ? {
            'conversation': {
              'id': 7,
              'product': product,
              'other': {'id': 9, 'name': 'City Unlock', 'store_name': 'City Unlock'},
              'unread_count': 0,
              'last_message_at': '2026-08-01T18:23:00+00:00',
            },
            'messages': messages,
          }
        : const <String, dynamic>{'messages': <dynamic>[]};

    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  Future<Response<dynamic>> postMultipart(
    String path, {
    required Map<String, dynamic> fields,
    required String fileField,
    required String filePath,
    String filename = 'upload.jpg',
    String? contentType,
  }) async {
    uploads.add({
      'path': path,
      'fields': fields,
      'fileField': fileField,
      'filePath': filePath,
      'filename': filename,
    });
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {
        'message': _message(
          99,
          type: 'image',
          body: fields['caption'] as String? ?? '',
          senderId: 1,
          imageUrl: 'https://cdn.example.com/chat/sent.jpg',
        ),
      },
    );
  }
}

final _honda = {
  'id': 12,
  'name': 'Honda',
  'slug': 'honda-civic-2016',
  'price': 45000.0,
  'image_url': 'https://cdn.example.com/products/honda.jpg',
};

Future<List<String>> _pumpChat(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1170, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final pushed = <String>[];
  final store = AppStore(api)
    ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

  final router = GoRouter(
    initialLocation: '/messages/7',
    routes: [
      GoRoute(path: '/messages/7', builder: (_, __) => const ChatScreen(conversationId: 7)),
      GoRoute(
        path: '/products/:slug',
        builder: (context, state) {
          pushed.add('/products/${state.pathParameters['slug']}');
          return const Scaffold(body: Text('product page'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppStore>.value(
      value: store,
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(useMaterial3: true),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }

  return pushed;
}

void main() {
  group('chat thread', () {
    testWidgets('call setup rows never show up as empty bubbles', (tester) async {
      await _pumpChat(tester, _FakeApiClient(product: _honda));

      // Six signalling rows came down the wire; none of them may be rendered.
      expect(find.text('Do you have the iPhone 12 in stock?'), findsOneWidget);
      expect(find.text('Voice call'), findsNothing);
      expect(
        find.descendant(of: find.byType(ListView), matching: find.text('')),
        findsNothing,
      );
    });

    testWidgets('a finished call reads as one line with its length', (tester) async {
      await _pumpChat(tester, _FakeApiClient(product: _honda));

      expect(find.textContaining('Voice call · 1m 5s'), findsOneWidget);
    });

    testWidgets('a photo message shows the photo and its caption', (tester) async {
      await _pumpChat(tester, _FakeApiClient(product: _honda));

      expect(find.text('Here it is'), findsOneWidget);
      final photos = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((w) => w.imageUrl);
      expect(photos, contains('https://cdn.example.com/chat/phone.jpg'));
    });

    testWidgets('the product strip shows the item with its price', (tester) async {
      await _pumpChat(tester, _FakeApiClient(product: _honda));

      expect(find.text('Honda'), findsOneWidget);
      expect(find.textContaining('45,000.00'), findsOneWidget);
      expect(find.text('About: Honda'), findsNothing);
    });

    testWidgets('tapping the strip opens the product page', (tester) async {
      final pushed = await _pumpChat(tester, _FakeApiClient(product: _honda));

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(pushed, ['/products/honda-civic-2016']);
    });

    testWidgets('a product without a slug is not tappable', (tester) async {
      final pushed = await _pumpChat(
        tester,
        _FakeApiClient(product: const {'id': 12, 'name': 'Honda'}),
      );

      expect(find.text('Honda'), findsOneWidget);
      expect(find.text('View'), findsNothing);
      expect(find.text('Chatting about this item'), findsOneWidget);
      expect(pushed, isEmpty);
    });

    testWidgets('a thread of nothing but signalling looks empty', (tester) async {
      await _pumpChat(
        tester,
        _FakeApiClient(
          product: _honda,
          messages: [
            _message(1, type: 'call_offer', body: 'Voice call'),
            _message(2, type: 'call_ice'),
          ],
        ),
      );

      expect(find.text('Say hello to the seller'), findsOneWidget);
    });

    testWidgets('the composer opens an attach grid instead of a low sheet', (tester) async {
      await _pumpChat(tester, _FakeApiClient(product: _honda));

      expect(find.byTooltip('Attach'), findsOneWidget);

      await tester.tap(find.byTooltip('Attach'));
      // The chat screen polls on a timer, so settle would never finish.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Album'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Send a photo'), findsNothing);
    });
  });

  group('AppStore.sendImageMessage', () {
    test('posts the photo to the chat image endpoint', () async {
      final api = _FakeApiClient(product: _honda);
      final store = AppStore(api)
        ..user = const AppUser(id: 1, name: 'Robert', email: 'robert@example.com');

      final msg = await store.sendImageMessage(
        7,
        '/tmp/honda.jpg',
        caption: 'Still available?',
        filename: 'honda.jpg',
      );

      expect(msg.isPhoto, isTrue);
      expect(msg.body, 'Still available?');
      expect(api.uploads.single['path'], '/messages/7/image');
      expect(api.uploads.single['fileField'], 'image');
      expect(api.uploads.single['filename'], 'honda.jpg');
      expect(api.uploads.single['fields'], {'caption': 'Still available?'});
    });
  });

  group('ChatMessage', () {
    ChatMessage parse(Map<String, dynamic> json) => ChatMessage.fromJson(json, myUserId: 1);

    test('knows which rows are call setup noise', () {
      for (final type in const ['call_offer', 'call_answer', 'call_ice', 'call_end']) {
        expect(parse(_message(1, type: type)).isSignalling, isTrue, reason: type);
      }
      for (final type in const ['text', 'image', 'video', 'voice', 'call_log', 'system']) {
        expect(parse(_message(1, type: type)).isSignalling, isFalse, reason: type);
      }
    });

    test('labels a call by how it ended', () {
      String label(Map<String, dynamic>? log) =>
          parse(_message(1, type: 'call_log', body: 'Voice call', callLog: log)).eventLabel;

      expect(label({'status': 'ended', 'duration_seconds': 125}), 'Voice call · 2m 5s');
      expect(label({'status': 'ended', 'duration_seconds': 8}), 'Voice call · 8s');
      expect(label({'status': 'ended', 'duration_seconds': 0}), 'Voice call');
      expect(label({'status': 'missed'}), 'Missed call');
      expect(label({'status': 'declined'}), 'Call declined');
      expect(label(null), 'Voice call');
    });

    test('a photo needs a url before it counts as one', () {
      expect(parse(_message(1, type: 'image', imageUrl: 'a.jpg')).isPhoto, isTrue);
      expect(parse(_message(1, type: 'image')).isPhoto, isFalse);
    });

    test('video and voice messages carry their media urls', () {
      final video = parse({
        'id': 1,
        'sender_id': 9,
        'type': 'video',
        'body': '',
        'metadata': {'video_url': 'https://cdn.example.com/v.mp4', 'duration_seconds': 12},
        'is_deleted': false,
      });
      final voice = parse({
        'id': 2,
        'sender_id': 9,
        'type': 'voice',
        'body': '',
        'metadata': {'voice_url': 'https://cdn.example.com/v.m4a', 'duration_seconds': 8},
        'is_deleted': false,
      });

      expect(video.isVideo, isTrue);
      expect(video.durationLabel, '0:12');
      expect(voice.isVoice, isTrue);
      expect(voice.durationLabel, '0:08');
    });
  });

  group('ConversationModel', () {
    ConversationModel parse(Object? latest, {Object? product}) => ConversationModel.fromJson({
          'id': 1,
          'other': const {'id': 9, 'name': 'City Unlock'},
          'product': product,
          'latest_message': latest,
        });

    test('previews a photo or a call instead of a blank line', () {
      expect(parse(const {'body': '', 'type': 'image'}).preview, 'Photo');
      expect(parse(const {'body': '', 'type': 'video'}).preview, 'Video');
      expect(parse(const {'body': '', 'type': 'voice'}).preview, 'Voice message');
      expect(parse(const {'body': 'Voice call', 'type': 'call_log'}).preview, 'Voice call');
      expect(parse(const {'body': 'Hello', 'type': 'text'}).preview, 'Hello');
      expect(parse(null).preview, 'Start the conversation');
    });

    test('reads the product slug, price and photo the strip needs', () {
      final c = parse(null, product: _honda);

      expect(c.productSlug, 'honda-civic-2016');
      expect(c.productPrice, 45000.0);
      expect(c.productImage, 'https://cdn.example.com/products/honda.jpg');
    });
  });
}
