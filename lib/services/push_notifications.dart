import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../store/app_store.dart';
import 'money_sound.dart';

const _prefsLastShownId = 'cityshop_push_last_shown_id';
const _androidChannelId = 'cityshop_alerts';
const _androidChannelName = 'CityShop alerts';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background/terminated delivery is handled by the OS notification payload.
  // Keep the handler registered so FCM can wake the app when configured.
}

/// Phone popup notifications for orders, messages, and other CityShop alerts.
class PushNotifications {
  PushNotifications._();

  static final PushNotifications instance = PushNotifications._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  AppStore? _store;
  Timer? _pollTimer;
  bool _ready = false;
  bool _fcmReady = false;
  String? _fcmToken;
  int _lastShownId = 0;
  void Function(String route)? _onOpenRoute;
  String Function()? _currentPath;
  bool _appInForeground = true;

  bool get isReady => _ready;
  bool get fcmReady => _fcmReady;

  Future<void> init(
    AppStore store, {
    void Function(String route)? onOpenRoute,
    String Function()? currentPath,
  }) async {
    if (_ready) {
      _store = store;
      _onOpenRoute = onOpenRoute;
      _currentPath = currentPath ?? _currentPath;
      return;
    }

    _store = store;
    _onOpenRoute = onOpenRoute;
    _currentPath = currentPath;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: 'Orders, messages, and account updates',
        importance: Importance.high,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    _lastShownId = prefs.getInt(_prefsLastShownId) ?? 0;

    await _tryInitFirebase();
    _ready = true;
  }

  Future<void> _tryInitFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onRemoteOpen);
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _openFromData(initial.data);
      }
      messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        await _registerTokenWithApi(token);
      });
      _fcmReady = true;
    } catch (e) {
      debugPrint('CityShop push: FCM unavailable ($e). Using local alerts.');
      _fcmReady = false;
    }
  }

  Future<bool> requestPermission({bool openSettingsIfDenied = false}) async {
    var granted = false;

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      granted = status.isGranted;
      if (!granted && openSettingsIfDenied && status.isPermanentlyDenied) {
        await openAppSettings();
      }
    } else if (Platform.isIOS) {
      final settings = await _local
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      granted = settings ?? false;
    }

    if (_fcmReady) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      granted = granted ||
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _fcmToken = token;
          await _registerTokenWithApi(token);
        }
      }
    }

    return granted;
  }

  Future<void> syncForLoggedInUser({bool requestIfNeeded = false}) async {
    final store = _store;
    if (store == null || !store.isLoggedIn) return;

    if (requestIfNeeded) {
      await requestPermission();
    }

    if (_fcmReady) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _fcmToken = token;
          await _registerTokenWithApi(token);
        }
      } catch (e) {
        debugPrint('CityShop push: token sync failed ($e)');
      }
    }

    await pollAndNotify(forceLoad: true);
    _startPolling();
  }

  Future<void> clearForLogout() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final token = _fcmToken;
    final store = _store;
    if (token != null && store != null) {
      try {
        await store.unregisterDeviceToken(token);
      } catch (_) {}
    }
    _fcmToken = null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(pollAndNotify());
    });
  }

  Future<void> pollAndNotify({bool forceLoad = false}) async {
    final store = _store;
    if (store == null || !store.isLoggedIn) return;

    final previousUnread = store.unreadNotifications;
    await store.refreshNotificationCounts();

    if (!forceLoad && store.unreadNotifications <= previousUnread && store.unreadNotifications == 0) {
      return;
    }

    if (forceLoad || store.unreadNotifications > previousUnread || store.unreadNotifications > 0) {
      try {
        await store.loadNotifications();
      } catch (_) {
        return;
      }
    }

    final fresh = store.notifications
        .where((n) => n.isUnread && n.id > _lastShownId)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    if (fresh.isEmpty) return;

    // Avoid dumping a huge backlog on first enable — show the newest few.
    final toShow = fresh.length > 5 ? fresh.sublist(fresh.length - 5) : fresh;
    for (final item in toShow) {
      if (_shouldSuppress(item)) continue;
      if (_isMoneyReceived(item)) {
        unawaited(MoneySound.playReceived());
      }
      await showLocal(item);
    }
    await _rememberShown(fresh.last.id);
  }

  void setAppInForeground(bool inForeground) {
    _appInForeground = inForeground;
  }

  bool _isMoneyReceived(AppNotificationItem item) {
    if (item.type != 'payment') return false;
    final title = item.title.toLowerCase();
    return title.contains('received') || title.contains('paid you');
  }

  bool _shouldSuppress(AppNotificationItem item) {
    if (!_appInForeground) return false;
    final path = _currentPath?.call() ?? '';
    final conversationId = item.conversationId;
    if (conversationId != null && path == '/messages/$conversationId') {
      return true;
    }
    return false;
  }

  Future<void> showLocal(AppNotificationItem item) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: 'Orders, messages, and account updates',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          item.body?.trim().isNotEmpty == true ? item.body!.trim() : item.title,
          contentTitle: item.title,
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _local.show(
      item.id,
      item.title,
      item.body,
      details,
      payload: _payloadFor(item),
    );
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'] ?? 'CityShop';
    final body = message.notification?.body ?? message.data['body'];
    final id = int.tryParse('${message.data['notification_id'] ?? ''}') ??
        DateTime.now().millisecondsSinceEpoch.remainder(1000000);
    final type = '${message.data['type'] ?? ''}';
    final titleText = '$title'.toLowerCase();
    if (type == 'payment' && (titleText.contains('received') || titleText.contains('paid you'))) {
      unawaited(MoneySound.playReceived());
    }

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: 'Orders, messages, and account updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: _payloadFromMap(message.data),
    );

    unawaited(_store?.refreshNotificationCounts());
  }

  void _onRemoteOpen(RemoteMessage message) => _openFromData(message.data);

  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final parts = Uri.splitQueryString(payload);
    _openFromData(parts);
  }

  void _openFromData(Map<String, dynamic> data) {
    final conversationId = data['conversation_id']?.toString();
    final orderId = data['order_id']?.toString();
    if (conversationId != null && conversationId.isNotEmpty) {
      _onOpenRoute?.call('/messages/$conversationId');
      return;
    }
    if (orderId != null && orderId.isNotEmpty) {
      _onOpenRoute?.call('/orders/$orderId');
      return;
    }
    _onOpenRoute?.call('/notifications');
  }

  String _payloadFor(AppNotificationItem item) {
    final params = <String, String>{
      'notification_id': '${item.id}',
      'type': item.type,
      if (item.conversationId != null) 'conversation_id': '${item.conversationId}',
      if (item.orderId != null) 'order_id': '${item.orderId}',
    };
    return Uri(queryParameters: params).query;
  }

  String _payloadFromMap(Map<String, dynamic> data) {
    final params = <String, String>{};
    data.forEach((key, value) {
      if (value != null) params[key] = '$value';
    });
    return Uri(queryParameters: params).query;
  }

  Future<void> _rememberShown(int id) async {
    if (id <= _lastShownId) return;
    _lastShownId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastShownId, id);
  }

  Future<void> _registerTokenWithApi(String token) async {
    final store = _store;
    if (store == null || !store.isLoggedIn) return;
    try {
      await store.registerDeviceToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } on ApiException catch (e) {
      debugPrint('CityShop push: register failed (${e.message})');
    } catch (e) {
      debugPrint('CityShop push: register failed ($e)');
    }
  }
}
