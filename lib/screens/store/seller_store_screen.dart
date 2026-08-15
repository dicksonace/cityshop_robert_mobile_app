import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../shop/shop_shell.dart';

class SellerStoreScreen extends StatefulWidget {
  const SellerStoreScreen({super.key, required this.slug});

  final String slug;

  @override
  State<SellerStoreScreen> createState() => _SellerStoreScreenState();
}

class _SellerStoreScreenState extends State<SellerStoreScreen> {
  bool loading = true;
  String? error;
  SellerStore? store;
  List<Product> products = [];
  final searchCtrl = TextEditingController();
  Timer? _livePoll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _livePoll?.cancel();
    searchCtrl.dispose();
    super.dispose();
  }

  void _syncLivePolling() {
    _livePoll?.cancel();
    if (!ApiConfig.livestreamEnabled || store?.isLive != true) return;
    _livePoll = Timer.periodic(const Duration(seconds: 10), (_) => _refreshLiveStatus());
  }

  Future<void> _refreshLiveStatus() async {
    final current = store;
    if (!mounted || current == null) return;
    try {
      final live = await context.read<AppStore>().fetchLivestream(widget.slug);
      if (!mounted) return;
      final stillLive = live != null && live.room != null && live.room!.roomName.isNotEmpty;
      if (stillLive == current.isLive && (stillLive ? live?.id == current.livestream?.id : true)) {
        return;
      }
      setState(() {
        store = current.copyWith(
          isLive: stillLive,
          livestream: stillLive ? live : null,
          clearLivestream: !stillLive,
        );
      });
      if (!stillLive) {
        _livePoll?.cancel();
      }
    } catch (_) {
      // keep current badge
    }
  }

  Future<void> _load({String? search}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context.read<AppStore>().fetchSellerStore(
            widget.slug,
            search: search,
          );
      if (!mounted) return;
      final app = context.read<AppStore>();
      if (result.store.isFollowing) {
        app.followingSellerIds = {...app.followingSellerIds, result.store.sellerId};
      }
      setState(() {
        store = result.store;
        products = result.products;
        loading = false;
      });
      _syncLivePolling();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final s = store;
    if (s == null || s.sellerId == 0) return;
    final app = context.read<AppStore>();
    if (!app.isLoggedIn) {
      context.push('/login');
      return;
    }
    try {
      final following = await app.toggleFollowSeller(s.sellerId);
      if (!mounted) return;
      setState(() {
        store = s.copyWith(
          followerCount: following
              ? s.followerCount + (s.isFollowing ? 0 : 1)
              : (s.followerCount - (s.isFollowing ? 1 : 0)).clamp(0, 1 << 30),
          isFollowing: following,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(following ? 'Following this seller' : 'Unfollowed this seller')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _chatSeller() async {
    final s = store;
    if (s == null || s.sellerId == 0) return;
    final app = context.read<AppStore>();
    if (!app.isLoggedIn) {
      context.push('/login');
      return;
    }
    try {
      final opened = await app.openConversation(sellerId: s.sellerId);
      if (!mounted) return;
      context.push('/messages/${opened.conversation.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _callSeller() async {
    final phone = store?.mobile ?? store?.whatsapp;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller phone is not available')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer')),
      );
    }
  }

  String get _storeLink {
    final slug = (store?.slug.isNotEmpty == true) ? store!.slug : widget.slug;
    return ApiConfig.storeShareUrl(slug);
  }

  Future<void> _shareStore() async {
    final name = store?.storeName.trim().isNotEmpty == true
        ? store!.storeName.trim()
        : 'this store';
    final url = _storeLink;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Shop at $name on CityShop\n$url',
        subject: name,
      ),
    );
  }

  Future<void> _copyStoreLink() async {
    await Clipboard.setData(ClipboardData(text: _storeLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Store link copied')),
    );
  }

  void _openSellerProfile() {
    final s = store;
    if (s == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SellerProfileSheet(
        store: s,
        onChat: () {
          Navigator.pop(ctx);
          _chatSeller();
        },
        onCall: () {
          Navigator.pop(ctx);
          _callSeller();
        },
      ),
    );
  }

  String? get _photoUrl {
    final raw = store?.shopPhoto;
    if (raw == null || raw.trim().isEmpty) return null;
    final resolved = ApiConfig.resolveMediaUrl(raw);
    return resolved.isEmpty ? null : resolved;
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    final photoUrl = _photoUrl;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: loading && s == null
          ? const FullPageLoader(label: 'Loading store…')
          : error != null && s == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: () => _load(), child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(search: searchCtrl.text.trim()),
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        expandedHeight: 176,
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        title: Text(s?.storeName ?? 'Store'),
                        actions: [
                          IconButton(
                            tooltip: 'Share store',
                            onPressed: _shareStore,
                            icon: const Icon(Icons.share_outlined),
                          ),
                        ],
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                              ),
                            ),
                            child: SafeArea(
                              bottom: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                                child: InkWell(
                                  onTap: _openSellerProfile,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      CircleAvatar(
                                        radius: 34,
                                        backgroundColor: Colors.white,
                                        backgroundImage: photoUrl != null
                                            ? CachedNetworkImageProvider(photoUrl)
                                            : null,
                                        child: photoUrl == null
                                            ? Text(
                                                (s?.storeName ?? 'S').substring(0, 1).toUpperCase(),
                                                style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 28,
                                                ),
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  s?.storeName ?? 'Store',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 22,
                                                    height: 1.15,
                                                  ),
                                                ),
                                                if (ApiConfig.livestreamEnabled && s?.isLive == true)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFDC2626),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: const Text(
                                                      'LIVE',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w900,
                                                        fontSize: 11,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              [
                                                if (s?.rating != null) '★ ${s!.rating!.toStringAsFixed(1)}',
                                                if (s?.totalSales != null) '${s!.totalSales} sales',
                                                '${s?.productCount ?? 0} products',
                                                if ((s?.followerCount ?? 0) > 0) '${s!.followerCount} followers',
                                              ].join(' · '),
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.92),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (s?.location != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                s!.location!,
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.85),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Text(
                                              'Tap for seller profile',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.9),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (ApiConfig.livestreamEnabled && s != null && s.isLive) ...[
                                _StoreLivePill(
                                  store: s,
                                  photoUrl: photoUrl,
                                  onTap: () => context.push('/live/${s.slug}'),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _toggleFollow,
                                      icon: Icon(
                                        (s?.isFollowing ?? false) ||
                                                context.watch<AppStore>().followingSellerIds.contains(s?.sellerId)
                                            ? Icons.person_remove_alt_1_outlined
                                            : Icons.person_add_alt_1_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        (s?.isFollowing ?? false) ||
                                                context.watch<AppStore>().followingSellerIds.contains(s?.sellerId)
                                            ? 'Following'
                                            : 'Follow',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _chatSeller,
                                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                      label: const Text('Chat'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _callSeller,
                                      icon: const Icon(Icons.phone_outlined, size: 18),
                                      label: const Text('Call'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  onTap: _copyStoreLink,
                                  onLongPress: _shareStore,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.link, size: 18, color: AppColors.primary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Store link',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _storeLink,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Copy link',
                                          onPressed: _copyStoreLink,
                                          icon: const Icon(Icons.copy_outlined, size: 18),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        IconButton(
                                          tooltip: 'Share',
                                          onPressed: _shareStore,
                                          icon: const Icon(Icons.share_outlined, size: 18),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if ((s?.description ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  s!.description!.trim(),
                                  style: const TextStyle(height: 1.4, color: AppColors.textSecondary),
                                ),
                              ],
                              if ((s?.businessAddress ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.place_outlined, size: 16, color: AppColors.textMuted),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        s!.businessAddress!,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              TextField(
                                controller: searchCtrl,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Search in this store',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.arrow_forward),
                                    onPressed: () => _load(search: searchCtrl.text.trim()),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                ),
                                onSubmitted: (q) => _load(search: q.trim()),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                products.isEmpty
                                    ? 'No products'
                                    : '${products.length} product${products.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (loading)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (products.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
                              child: Center(child: Text('No products found in this store')),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.68,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => ProductCard(product: products[index]),
                                childCount: products.length,
                              ),
                            ),
                          ),
                        // Match web store page: About + Contact under the product grid.
                        SliverToBoxAdapter(
                          child: _StoreAboutContact(store: s!),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _StoreAboutContact extends StatelessWidget {
  const _StoreAboutContact({
    required this.store,
  });

  final SellerStore store;

  Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String? get _locationLine {
    final parts = [
      store.city?.trim(),
      store.region?.trim(),
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty && (store.digitalAddress ?? '').trim().isEmpty) {
      return null;
    }
    final base = parts.join(', ');
    final digital = (store.digitalAddress ?? '').trim();
    if (base.isEmpty) return digital;
    if (digital.isEmpty) return base;
    return '$base · $digital';
  }

  bool get _hasContact {
    return _locationLine != null ||
        (store.mobile ?? '').trim().isNotEmpty ||
        (store.whatsapp ?? '').trim().isNotEmpty ||
        (store.email ?? '').trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final about = (store.description ?? '').trim();
    final aboutText = about.isNotEmpty ? about : 'Welcome to our store on CityShop.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About ${store.storeName}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 10),
                Text(
                  aboutText,
                  style: const TextStyle(
                    height: 1.45,
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_hasContact) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 12),
                  if (_locationLine != null)
                    _ContactRow(
                      icon: Icons.place_outlined,
                      child: Text(
                        _locationLine!,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.35),
                      ),
                    ),
                  if ((store.mobile ?? '').trim().isNotEmpty)
                    _ContactRow(
                      icon: Icons.phone_outlined,
                      onTap: () => _open(Uri(scheme: 'tel', path: store.mobile!.replaceAll(' ', ''))),
                      child: Text(
                        store.mobile!.trim(),
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  if ((store.whatsapp ?? '').trim().isNotEmpty)
                    _ContactRow(
                      icon: Icons.chat,
                      iconColor: const Color(0xFF16A34A),
                      onTap: () {
                        final digits = store.whatsapp!.replaceAll(RegExp(r'\D'), '');
                        _open(Uri.parse('https://wa.me/$digits'));
                      },
                      child: const Text(
                        'WhatsApp',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  if ((store.email ?? '').trim().isNotEmpty)
                    _ContactRow(
                      icon: Icons.mail_outline,
                      onTap: () => _open(Uri(scheme: 'mailto', path: store.email!.trim())),
                      child: Text(
                        store.email!.trim(),
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.child,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor ?? AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _SellerProfileSheet extends StatelessWidget {
  const _SellerProfileSheet({
    required this.store,
    required this.onChat,
    required this.onCall,
  });

  final SellerStore store;
  final VoidCallback onChat;
  final VoidCallback onCall;

  String? get _photoUrl {
    final raw = store.shopPhoto;
    if (raw == null || raw.trim().isEmpty) return null;
    final resolved = ApiConfig.resolveMediaUrl(raw);
    return resolved.isEmpty ? null : resolved;
  }

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _photoUrl;
    final memberSince = store.approvedAt == null
        ? null
        : DateFormat.yMMMM().format(store.approvedAt!.toLocal());

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (photoUrl != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 7,
                      child: CachedNetworkImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  28 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.ringOrange,
                          backgroundImage:
                              photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                          child: photoUrl == null
                              ? Text(
                                  store.storeName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      store.storeName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified, size: 18, color: Color(0xFF3B82F6)),
                                ],
                              ),
                              if ((store.sellerName ?? '').trim().isNotEmpty)
                                Text(
                                  'Run by ${store.sellerName}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          icon: Icons.star,
                          iconColor: Colors.amber,
                          label: store.reviewCount > 0 && store.rating != null
                              ? '${store.rating!.toStringAsFixed(1)} rating · ${store.reviewCount} review${store.reviewCount == 1 ? '' : 's'}'
                              : 'No reviews yet',
                          bg: const Color(0xFFFFFBEB),
                          fg: const Color(0xFFB45309),
                        ),
                        if (store.isBusinessRegistered)
                          _chip(
                            icon: Icons.business,
                            label: 'Registered business',
                            bg: const Color(0xFFEFF6FF),
                            fg: const Color(0xFF1D4ED8),
                          ),
                        _chip(
                          icon: Icons.verified_user_outlined,
                          label: 'Verified seller',
                          bg: const Color(0xFFECFDF5),
                          fg: const Color(0xFF047857),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    _detail(
                      Icons.inventory_2_outlined,
                      '${store.totalSales ?? 0} sales',
                      '${store.productCount} products listed',
                    ),
                    if (store.location != null)
                      _detail(Icons.place_outlined, 'Location', store.location!),
                    if ((store.businessAddress ?? '').trim().isNotEmpty)
                      _detail(Icons.storefront_outlined, 'Shop address', store.businessAddress!.trim()),
                    if ((store.digitalAddress ?? '').trim().isNotEmpty)
                      _detail(Icons.pin_drop_outlined, 'Digital address', store.digitalAddress!.trim()),
                    if ((store.residentialAddress ?? '').trim().isNotEmpty &&
                        (store.businessAddress ?? '').trim().isEmpty)
                      _detail(Icons.home_outlined, 'Address', store.residentialAddress!.trim()),
                    if ((store.mobile ?? '').trim().isNotEmpty)
                      _detail(
                        Icons.phone_outlined,
                        'Phone',
                        store.mobile!.trim(),
                        onTap: () => _launch(Uri(scheme: 'tel', path: store.mobile!.replaceAll(' ', ''))),
                      ),
                    if ((store.whatsapp ?? '').trim().isNotEmpty)
                      _detail(
                        Icons.chat,
                        'WhatsApp',
                        store.whatsapp!.trim(),
                        onTap: () {
                          final digits = store.whatsapp!.replaceAll(RegExp(r'\D'), '');
                          _launch(Uri.parse('https://wa.me/$digits'));
                        },
                      ),
                    if ((store.email ?? '').trim().isNotEmpty)
                      _detail(
                        Icons.mail_outline,
                        'Email',
                        store.email!.trim(),
                        onTap: () => _launch(Uri(scheme: 'mailto', path: store.email!.trim())),
                      ),
                    if (memberSince != null) _detail(Icons.calendar_month_outlined, 'Member since', memberSince),
                    if ((store.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      const Text('About this store', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        store.description!.trim(),
                        style: const TextStyle(height: 1.45, color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onCall,
                            icon: const Icon(Icons.phone_outlined, size: 18),
                            label: const Text('Call'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: onChat,
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Message'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? fg),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    final child = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: onTap != null ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }
}

class _StoreLivePill extends StatelessWidget {
  const _StoreLivePill({
    required this.store,
    required this.onTap,
    this.photoUrl,
  });

  final SellerStore store;
  final VoidCallback onTap;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final title = (store.livestream?.title ?? '').trim().isNotEmpty
        ? store.livestream!.title!.trim()
        : store.storeName;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFED7AA), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFFFF7ED),
                    backgroundImage:
                        photoUrl != null ? CachedNetworkImageProvider(photoUrl!) : null,
                    child: photoUrl == null
                        ? Text(
                            store.storeName.isNotEmpty ? store.storeName[0].toUpperCase() : 'S',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
