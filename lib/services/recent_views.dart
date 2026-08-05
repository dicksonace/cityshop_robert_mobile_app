import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'cityshop_recent_views';
const _maxItems = 20;

/// Local recently-viewed product ids — mirrors web `recent-views.ts`.
class RecentViews {
  RecentViews._();

  static Future<List<Map<String, dynamic>>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return parsed
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['id'] is num)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<int>> getIds() async {
    final items = await _readAll();
    return items.map((e) => (e['id'] as num).toInt()).toList();
  }

  static Future<void> record({required int id, int? categoryId}) async {
    if (id <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await _readAll();
    final next = <Map<String, dynamic>>[
      {
        'id': id,
        if (categoryId != null) 'category_id': categoryId,
        'at': DateTime.now().millisecondsSinceEpoch,
      },
      ...existing.where((e) => (e['id'] as num).toInt() != id),
    ];
    await prefs.setString(
      _storageKey,
      jsonEncode(next.take(_maxItems).toList()),
    );
  }
}
