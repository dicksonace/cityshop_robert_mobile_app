enum ChatTextKind { plain, url, phone }

class ChatTextSegment {
  const ChatTextSegment({required this.text, this.kind = ChatTextKind.plain});

  final String text;
  final ChatTextKind kind;
}

class CityShopDeepLink {
  const CityShopDeepLink({
    required this.kind,
    required this.slug,
    required this.inAppPath,
  });

  /// product | store | live
  final String kind;
  final String slug;
  final String inAppPath;
}

final _urlPattern = RegExp(
  r'(?:https?:\/\/[^\s<>"\]]+|www\.[^\s<>"\]]+|cityshop:\/\/[^\s<>"\]]+)',
  caseSensitive: false,
);

final _phonePattern = RegExp(
  r'(?:\+233|233|0)[\s-]*\d(?:[\s-]*\d){8}',
);

String _trimTrailingPunctuation(String value) {
  return value.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
}

bool _isCityShopHost(String host) {
  final h = host.toLowerCase().replaceFirst('www.', '');
  return h == 'cityunlock.net' ||
      h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '10.0.2.2';
}

/// Turns a pasted CityShop URL into an in-app path, or null if it is not ours.
CityShopDeepLink? parseCityShopDeepLink(String raw) {
  var value = raw.trim();
  if (value.startsWith('www.')) {
    value = 'https://$value';
  }

  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty && uri.scheme != 'cityshop') {
    return null;
  }

  String path;
  if (uri.scheme == 'cityshop') {
    if (uri.host == 'app') {
      path = uri.path;
    } else {
      path = '/${uri.host}${uri.path}';
    }
  } else {
    if (!_isCityShopHost(uri.host)) {
      return null;
    }
    path = uri.path;
  }

  if (path.startsWith('/app/')) {
    path = path.substring(4);
  }
  if (path.startsWith('/product/') && !path.startsWith('/products/')) {
    path = '/products/${path.substring('/product/'.length)}';
  } else if (path.startsWith('/store/') && !path.startsWith('/stores/')) {
    path = '/stores/${path.substring('/store/'.length)}';
  }

  path = path.replaceFirst(RegExp(r'/$'), '');

  final product = RegExp(r'^/products/([^/]+)$').firstMatch(path);
  if (product != null) {
    return CityShopDeepLink(kind: 'product', slug: product.group(1)!, inAppPath: path);
  }
  final store = RegExp(r'^/stores/([^/]+)$').firstMatch(path);
  if (store != null) {
    return CityShopDeepLink(kind: 'store', slug: store.group(1)!, inAppPath: path);
  }
  final live = RegExp(r'^/live/([^/]+)$').firstMatch(path);
  if (live != null) {
    return CityShopDeepLink(kind: 'live', slug: live.group(1)!, inAppPath: path);
  }
  return null;
}

CityShopDeepLink? firstCityShopLinkIn(String text) {
  for (final match in _urlPattern.allMatches(text)) {
    final url = _trimTrailingPunctuation(match.group(0)!);
    final link = parseCityShopDeepLink(url);
    if (link != null) return link;
  }
  return null;
}

List<ChatTextSegment> parseChatText(String text) {
  if (text.isEmpty) return const [];

  final occupied = <_Range>[];
  final found = <_Marked>[];

  for (final match in _urlPattern.allMatches(text)) {
    final raw = match.group(0)!;
    final trimmed = _trimTrailingPunctuation(raw);
    final end = match.start + trimmed.length;
    occupied.add(_Range(match.start, end));
    found.add(_Marked(match.start, end, ChatTextKind.url));
  }

  for (final match in _phonePattern.allMatches(text)) {
    if (occupied.any((r) => r.overlaps(match.start, match.end))) {
      continue;
    }
    if (match.start > 0 && _isDigit(text.codeUnitAt(match.start - 1))) {
      continue;
    }
    occupied.add(_Range(match.start, match.end));
    found.add(_Marked(match.start, match.end, ChatTextKind.phone));
  }

  found.sort((a, b) => a.start.compareTo(b.start));

  final segments = <ChatTextSegment>[];
  var cursor = 0;
  for (final item in found) {
    if (item.start > cursor) {
      segments.add(ChatTextSegment(text: text.substring(cursor, item.start)));
    }
    segments.add(ChatTextSegment(
      text: text.substring(item.start, item.end),
      kind: item.kind,
    ));
    cursor = item.end;
  }
  if (cursor < text.length) {
    segments.add(ChatTextSegment(text: text.substring(cursor)));
  }
  return segments;
}

bool _isDigit(int code) => code >= 48 && code <= 57;

class _Range {
  const _Range(this.start, this.end);
  final int start;
  final int end;
  bool overlaps(int otherStart, int otherEnd) => otherStart < end && otherEnd > start;
}

class _Marked {
  const _Marked(this.start, this.end, this.kind);
  final int start;
  final int end;
  final ChatTextKind kind;
}
