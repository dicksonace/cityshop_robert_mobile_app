import 'dart:async';
import 'dart:convert';

import 'package:dart_pusher_channels/dart_pusher_channels.dart';

import '../api/api_config.dart';
import '../models/models.dart';

class RealtimeConfig {
  const RealtimeConfig({
    required this.enabled,
    required this.key,
    required this.host,
    required this.port,
    required this.scheme,
    required this.authEndpoint,
  });

  final bool enabled;
  final String key;
  final String host;
  final int port;
  final String scheme;
  final String authEndpoint;

  factory RealtimeConfig.fromJson(Map<String, dynamic> json) {
    return RealtimeConfig(
      enabled: json['enabled'] == true,
      key: (json['key'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: (json['port'] as num?)?.toInt() ?? 443,
      scheme: (json['scheme'] ?? 'https').toString(),
      authEndpoint: (json['auth_endpoint'] ?? '').toString(),
    );
  }

  bool get isUsable =>
      enabled && key.isNotEmpty && host.isNotEmpty && authEndpoint.isNotEmpty;
}

/// Subscribes to a conversation's private Reverb channel for live messages.
class ConversationRealtime {
  ConversationRealtime({
    required this.config,
    required this.token,
    required this.conversationId,
    required this.myUserId,
    required this.onMessage,
  });

  final RealtimeConfig config;
  final String token;
  final int conversationId;
  final int myUserId;
  final void Function(ChatMessage message) onMessage;

  PusherChannelsClient? _client;
  StreamSubscription<void>? _connectionSub;
  StreamSubscription<ChannelReadEvent>? _eventSub;
  bool _disposed = false;

  Future<bool> start() async {
    if (!config.isUsable || token.isEmpty) return false;

    final useTls = config.scheme == 'https' || config.scheme == 'wss';
    final options = PusherChannelsOptions.fromHost(
      scheme: useTls ? 'wss' : 'ws',
      host: config.host,
      key: config.key,
      port: config.port,
      shouldSupplyMetadataQueries: true,
      metadata: PusherChannelsOptionsMetadata.byDefault(),
    );

    final client = PusherChannelsClient.websocket(
      options: options,
      connectionErrorHandler: (exception, trace, refresh) {
        refresh();
      },
    );
    _client = client;

    final authUri = Uri.parse(
      config.authEndpoint.isNotEmpty
          ? config.authEndpoint
          : '${ApiConfig.baseUrl}/broadcasting/auth',
    );

    final channel = client.privateChannel(
      'private-conversation.$conversationId',
      authorizationDelegate:
          EndpointAuthorizableChannelTokenAuthorizationDelegate.forPrivateChannel(
        authorizationEndpoint: authUri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
    );

    _eventSub = channel.bind('message.sent').listen(_handleEvent);

    _connectionSub = client.onConnectionEstablished.listen((_) {
      channel.subscribeIfNotUnsubscribed();
    });

    await client.connect();
    return !_disposed;
  }

  void _handleEvent(ChannelReadEvent event) {
    try {
      final raw = event.data;
      final decoded = raw is String
          ? jsonDecode(raw)
          : raw is Map
              ? raw
              : null;
      if (decoded is! Map) return;
      final messageJson = decoded['message'];
      if (messageJson is! Map) return;
      final message = ChatMessage.fromJson(
        Map<String, dynamic>.from(messageJson),
        myUserId: myUserId,
      );
      onMessage(message);
    } catch (_) {
      // ignore malformed payloads
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _eventSub?.cancel();
    await _connectionSub?.cancel();
    _eventSub = null;
    _connectionSub = null;
    _client?.dispose();
    _client = null;
  }
}
