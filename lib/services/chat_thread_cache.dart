import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Local cache for chat inbox + threads so chats stay readable offline.
class ChatThreadCache {
  ChatThreadCache._();

  static const _maxMessages = 250;

  static String _threadKey(int userId, int conversationId) =>
      'cityshop_chat_thread_${userId}_$conversationId';

  static String _inboxKey(int userId) => 'cityshop_chat_inbox_$userId';

  static Future<void> saveThread({
    required int userId,
    required int conversationId,
    required Map<String, dynamic> conversation,
    required List<Map<String, dynamic>> messages,
  }) async {
    if (userId <= 0 || conversationId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;
    await prefs.setString(
      _threadKey(userId, conversationId),
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'conversation': conversation,
        'messages': trimmed,
      }),
    );
  }

  /// Keep a just-sent transfer in the saved thread so leaving the chat
  /// and coming back does not collapse it into the previous receipt.
  static Future<void> appendMessage({
    required int userId,
    required int conversationId,
    required Map<String, dynamic> message,
  }) async {
    if (userId <= 0 || conversationId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _threadKey(userId, conversationId);
    final raw = prefs.getString(key);
    Map<String, dynamic> payload = {
      'saved_at': DateTime.now().toIso8601String(),
      'conversation': <String, dynamic>{'id': conversationId},
      'messages': <Map<String, dynamic>>[],
    };
    if (raw != null && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map) {
          payload = Map<String, dynamic>.from(parsed);
        }
      } catch (_) {}
    }
    final existing = payload['messages'];
    final messages = existing is List
        ? existing.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final id = message['id'];
    final ref = message['transfer'] is Map
        ? (message['transfer'] as Map)['reference']
        : (message['metadata'] is Map ? (message['metadata'] as Map)['transfer'] : null);
    final reference = ref is Map ? ref['reference'] : null;
    final already = messages.any((row) {
      if (id != null && row['id'] == id) return true;
      final rowTransfer = row['transfer'] ?? (row['metadata'] is Map ? (row['metadata'] as Map)['transfer'] : null);
      final rowRef = rowTransfer is Map ? rowTransfer['reference'] : null;
      return reference != null && rowRef != null && rowRef == reference;
    });
    if (!already) messages.add(message);
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;
    payload['saved_at'] = DateTime.now().toIso8601String();
    payload['messages'] = trimmed;
    await prefs.setString(key, jsonEncode(payload));
  }

  static Future<({ConversationModel conversation, List<ChatMessage> messages})?> loadThread({
    required int userId,
    required int conversationId,
  }) async {
    if (userId <= 0 || conversationId <= 0) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_threadKey(userId, conversationId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final conv = parsed['conversation'];
      final msgs = parsed['messages'];
      if (conv is! Map) return null;
      final conversation = ConversationModel.fromJson(Map<String, dynamic>.from(conv));
      final messages = msgs is List
          ? msgs
              .whereType<Map>()
              .map(
                (e) => ChatMessage.fromJson(
                  Map<String, dynamic>.from(e),
                  myUserId: userId,
                ),
              )
              .toList()
          : <ChatMessage>[];
      return (conversation: conversation, messages: messages);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveInbox({
    required int userId,
    required List<Map<String, dynamic>> conversations,
  }) async {
    if (userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _inboxKey(userId),
      jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'conversations': conversations,
      }),
    );
  }

  static Future<List<ConversationModel>?> loadInbox({required int userId}) async {
    if (userId <= 0) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_inboxKey(userId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final data = parsed['conversations'];
      if (data is! List) return null;
      return data
          .whereType<Map>()
          .map((e) => ConversationModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
