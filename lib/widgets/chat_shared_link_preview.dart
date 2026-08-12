import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../models/models.dart';
import '../store/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/chat_text_links.dart';

final _money = NumberFormat.currency(locale: 'en_GH', symbol: 'GH₵', decimalDigits: 2);
final _productCache = <String, Product?>{};

class ChatSharedLinkPreview extends StatefulWidget {
  const ChatSharedLinkPreview({
    super.key,
    required this.link,
    required this.mine,
  });

  final CityShopDeepLink link;
  final bool mine;

  @override
  State<ChatSharedLinkPreview> createState() => _ChatSharedLinkPreviewState();
}

class _ChatSharedLinkPreviewState extends State<ChatSharedLinkPreview> {
  Product? product;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatSharedLinkPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link.slug != widget.link.slug || oldWidget.link.kind != widget.link.kind) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.link.kind != 'product') {
      if (mounted) setState(() => loading = false);
      return;
    }
    final cached = _productCache[widget.link.slug];
    if (cached != null) {
      setState(() {
        product = cached;
        loading = false;
      });
      return;
    }
    if (_productCache.containsKey(widget.link.slug)) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      final loaded = await context.read<AppStore>().fetchProduct(widget.link.slug);
      _productCache[widget.link.slug] = loaded;
      if (!mounted) return;
      setState(() {
        product = loaded;
        loading = false;
      });
    } on ApiException {
      _productCache[widget.link.slug] = null;
      if (mounted) setState(() => loading = false);
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.link.kind != 'product') {
      return _SimpleLinkCard(
        title: widget.link.kind == 'store' ? 'Open store' : 'Watch live',
        subtitle: 'cityunlock.net',
        mine: widget.mine,
        onTap: () => context.push(widget.link.inAppPath),
      );
    }

    if (loading && product == null) {
      return const SizedBox.shrink();
    }
    final p = product;
    if (p == null) {
      return _SimpleLinkCard(
        title: 'Open product',
        subtitle: 'cityunlock.net',
        mine: widget.mine,
        onTap: () => context.push(widget.link.inAppPath),
      );
    }

    final photo = ApiConfig.resolveMediaUrl(p.primaryImageUrl);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: widget.mine ? Colors.white.withValues(alpha: 0.16) : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push(widget.link.inAppPath),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photo.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: widget.mine ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _money.format(p.effectivePrice),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: widget.mine ? Colors.white : AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'cityunlock.net',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.mine ? Colors.white70 : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleLinkCard extends StatelessWidget {
  const _SimpleLinkCard({
    required this.title,
    required this.subtitle,
    required this.mine,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: mine ? Colors.white.withValues(alpha: 0.16) : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Icon(Icons.link, color: mine ? Colors.white : AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: mine ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: mine ? Colors.white70 : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: mine ? Colors.white70 : AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
