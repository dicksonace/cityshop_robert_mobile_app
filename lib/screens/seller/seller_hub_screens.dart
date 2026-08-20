import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _asMaps(dynamic value) {
  if (value is! List) return [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

class SellerReviewsScreen extends StatefulWidget {
  const SellerReviewsScreen({super.key});

  @override
  State<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends State<SellerReviewsScreen> {
  bool loading = true;
  String? error;
  String filter = 'all';
  List<Map<String, dynamic>> reviews = [];
  Map<String, dynamic> stats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerReviews(filter: filter);
      if (!mounted) return;
      setState(() {
        reviews = _asMaps(data['data']);
        stats = _asMap(data['stats']);
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _reply(int id) async {
    final ctrl = TextEditingController();
    final ok = await showAppSheet<bool>(
      context: context,
      builder: (ctx) => SheetShell(
        action: FilledButton(
          onPressed: () {
            if (ctrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('Post reply'),
        ),
        children: [
          const Text('Reply to review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Your reply')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<AppStore>().replySellerReview(id, ctrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply posted.')));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reviews')),
      body: loading
          ? const FullPageLoader(label: 'Loading reviews…')
          : error != null
              ? Center(child: Text(error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Text(
                        'Average ${stats['average'] ?? 0} · ${stats['total'] ?? 0} reviews · ${stats['unreplied'] ?? 0} waiting',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(label: const Text('All'), selected: filter == 'all', onSelected: (_) {
                            setState(() => filter = 'all');
                            _load();
                          }),
                          ChoiceChip(label: const Text('Unreplied'), selected: filter == 'unreplied', onSelected: (_) {
                            setState(() => filter = 'unreplied');
                            _load();
                          }),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (reviews.isEmpty) const Text('No reviews yet.', style: TextStyle(color: AppColors.textSecondary)),
                      ...reviews.map((review) {
                        final id = (review['id'] as num?)?.toInt() ?? 0;
                        final product = _asMap(review['product']);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${review['buyer_name'] ?? 'Buyer'} · ${review['rating']}/5', style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(product['name'] as String? ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                if ((review['comment'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: 6),
                                  Text(review['comment'] as String),
                                ],
                                if ((review['seller_reply'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: 8),
                                  Text('You: ${review['seller_reply']}', style: const TextStyle(color: AppColors.textSecondary)),
                                ] else
                                  TextButton(onPressed: () => _reply(id), child: const Text('Reply')),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

class SellerPromotionsScreen extends StatefulWidget {
  const SellerPromotionsScreen({super.key});

  @override
  State<SellerPromotionsScreen> createState() => _SellerPromotionsScreenState();
}

class _SellerPromotionsScreenState extends State<SellerPromotionsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> coupons = [];
  List<Map<String, dynamic>> types = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerPromotions();
      if (!mounted) return;
      setState(() {
        coupons = _asMaps(data['data']);
        types = _asMaps(data['types']);
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _create() async {
    var type = types.isNotEmpty ? types.first['value'] as String : 'percentage';
    final code = TextEditingController();
    final value = TextEditingController();
    final minOrder = TextEditingController();
    final ok = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SheetShell(
              action: FilledButton(
                onPressed: () async {
                  try {
                    await context.read<AppStore>().createSellerPromotion({
                      'code': code.text.trim(),
                      'type': type,
                      'value': double.tryParse(value.text.trim()) ?? 0,
                      if (minOrder.text.trim().isNotEmpty) 'min_order_amount': double.tryParse(minOrder.text.trim()),
                      'is_active': true,
                    });
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on ApiException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                child: const Text('Create coupon'),
              ),
              children: [
                const Text('New coupon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final item in types)
                      DropdownMenuItem(value: item['value'] as String, child: Text(item['label'] as String? ?? '')),
                  ],
                  onChanged: (v) {
                    if (v != null) setModal(() => type = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Value (% or GHS)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minOrder,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Minimum order (optional)'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Promotions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Add coupon'),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading coupons…')
          : error != null
              ? Center(child: Text(error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    children: [
                      if (coupons.isEmpty) const Text('No coupons yet.', style: TextStyle(color: AppColors.textSecondary)),
                      ...coupons.map((coupon) {
                        final id = (coupon['id'] as num?)?.toInt() ?? 0;
                        final active = coupon['is_active'] == true;
                        return Card(
                          child: SwitchListTile(
                            title: Text(coupon['code'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${coupon['type']} · ${coupon['value']} · used ${coupon['used_count'] ?? 0}'),
                            value: active,
                            onChanged: (v) async {
                              await context.read<AppStore>().updateSellerPromotion(id, isActive: v);
                              await _load();
                            },
                            secondary: IconButton(
                              onPressed: () async {
                                await context.read<AppStore>().deleteSellerPromotion(id);
                                await _load();
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

class SellerFollowersScreen extends StatefulWidget {
  const SellerFollowersScreen({super.key});

  @override
  State<SellerFollowersScreen> createState() => _SellerFollowersScreenState();
}

class _SellerFollowersScreenState extends State<SellerFollowersScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> followers = [];
  int total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerFollowers();
      if (!mounted) return;
      setState(() {
        followers = _asMaps(data['data']);
        total = (data['total'] as num?)?.toInt() ?? followers.length;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Followers ($total)')),
      body: loading
          ? const FullPageLoader(label: 'Loading followers…')
          : error != null
              ? Center(child: Text(error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: followers.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Text('No followers yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
                          itemCount: followers.length,
                          itemBuilder: (_, i) {
                            final user = _asMap(followers[i]['user']);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (user['avatar'] as String?)?.isNotEmpty == true
                                    ? CachedNetworkImageProvider(user['avatar'] as String)
                                    : null,
                                child: (user['avatar'] as String?)?.isNotEmpty == true
                                    ? null
                                    : Text((user['name'] as String? ?? '?').characters.first.toUpperCase()),
                              ),
                              title: Text(user['name'] as String? ?? 'Buyer', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(user['mobile'] as String? ?? ''),
                            );
                          },
                        ),
                ),
    );
  }
}

class SellerRefundsScreen extends StatefulWidget {
  const SellerRefundsScreen({super.key});

  @override
  State<SellerRefundsScreen> createState() => _SellerRefundsScreenState();
}

class _SellerRefundsScreenState extends State<SellerRefundsScreen> {
  bool loading = true;
  String? error;
  String status = 'open';
  List<Map<String, dynamic>> disputes = [];
  Map<String, dynamic> counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerRefunds(status: status);
      if (!mounted) return;
      setState(() {
        disputes = _asMaps(data['data']);
        counts = _asMap(data['counts']);
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Refunds')),
      body: loading
          ? const FullPageLoader(label: 'Loading refunds…')
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final item in [
                            ('open', 'Open'),
                            ('under_review', 'Review'),
                            ('resolved_buyer', 'Buyer'),
                            ('resolved_seller', 'Seller'),
                            ('all', 'All'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${item.$2} ${(counts[item.$1] as num?)?.toInt() ?? ''}'),
                                selected: status == item.$1,
                                onSelected: (_) {
                                  setState(() => status = item.$1);
                                  _load();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: disputes.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 80),
                                  Text('No refund cases in this filter.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                                itemCount: disputes.length,
                                itemBuilder: (_, i) {
                                  final item = disputes[i];
                                  final orderItemId = (item['order_item_id'] as num?)?.toInt();
                                  return Card(
                                    child: ListTile(
                                      onTap: orderItemId == null ? null : () => context.push('/seller/orders/$orderItemId'),
                                      title: Text(item['product_name'] as String? ?? 'Order', style: const TextStyle(fontWeight: FontWeight.w800)),
                                      subtitle: Text(
                                        [
                                          item['order_number'],
                                          item['buyer_name'],
                                          item['reason'],
                                          (item['status'] as String?)?.replaceAll('_', ' '),
                                        ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class SellerStoreAppearanceScreen extends StatefulWidget {
  const SellerStoreAppearanceScreen({super.key});

  @override
  State<SellerStoreAppearanceScreen> createState() => _SellerStoreAppearanceScreenState();
}

class _SellerStoreAppearanceScreenState extends State<SellerStoreAppearanceScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  Map<String, dynamic> store = {};
  final name = TextEditingController();
  final slogan = TextEditingController();
  final description = TextEditingController();
  final announcement = TextEditingController();
  final promo = TextEditingController();
  final facebook = TextEditingController();
  final instagram = TextEditingController();
  final website = TextEditingController();
  bool announcementOn = false;
  bool promoOn = false;
  bool sectionFeatured = true;
  bool sectionAbout = true;
  bool sectionContact = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    slogan.dispose();
    description.dispose();
    announcement.dispose();
    promo.dispose();
    facebook.dispose();
    instagram.dispose();
    website.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerStore();
      if (!mounted) return;
      name.text = data['store_name'] as String? ?? '';
      slogan.text = data['slogan'] as String? ?? '';
      description.text = data['description'] as String? ?? '';
      final announcementData = _asMap(data['announcement']);
      final promoData = _asMap(data['promo']);
      final social = _asMap(data['social']);
      final sections = _asMap(data['sections_enabled']);
      announcement.text = announcementData['text'] as String? ?? '';
      promo.text = promoData['text'] as String? ?? '';
      facebook.text = social['facebook'] as String? ?? '';
      instagram.text = social['instagram'] as String? ?? '';
      website.text = social['website'] as String? ?? '';
      announcementOn = announcementData['enabled'] == true;
      promoOn = promoData['enabled'] == true;
      sectionFeatured = sections['featured'] != false;
      sectionAbout = sections['about'] != false;
      sectionContact = sections['contact'] != false;
      setState(() {
        store = data;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _save({bool publish = false}) async {
    setState(() => saving = true);
    try {
      final app = context.read<AppStore>();
      var data = await app.updateSellerStore(
        storeName: name.text.trim(),
        slogan: slogan.text.trim(),
        description: description.text.trim(),
        preset: store['preset'] as String?,
        announcementEnabled: announcementOn,
        announcementText: announcement.text.trim(),
        promoEnabled: promoOn,
        promoText: promo.text.trim(),
        socialFacebook: facebook.text.trim(),
        socialInstagram: instagram.text.trim(),
        website: website.text.trim(),
        sectionsEnabled: {
          'featured': sectionFeatured,
          'about': sectionAbout,
          'contact': sectionContact,
          'announcement': announcementOn,
          'promo': promoOn,
        },
      );
      if (publish) {
        data = await app.publishSellerStore();
      }
      if (!mounted) return;
      setState(() {
        store = data;
        saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] as String? ?? 'Saved.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pick(bool logo) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (picked == null) return;
    setState(() => saving = true);
    try {
      final data = logo
          ? await context.read<AppStore>().uploadSellerStoreLogo(picked.path)
          : await context.read<AppStore>().uploadSellerStoreCover(picked.path);
      if (!mounted) return;
      setState(() {
        store = data;
        saving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickHero() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 82, limit: 8);
    if (picked.isEmpty) return;
    setState(() => saving = true);
    try {
      final data = await context.read<AppStore>().uploadSellerStoreHero(picked.map((e) => e.path).toList());
      if (!mounted) return;
      setState(() {
        store = data;
        saving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeHero(String path) async {
    setState(() => saving = true);
    try {
      final data = await context.read<AppStore>().updateSellerStore(removeHeroPaths: [path]);
      if (!mounted) return;
      setState(() {
        store = data;
        saving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickPromo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (picked == null) return;
    setState(() => saving = true);
    try {
      final data = await context.read<AppStore>().uploadSellerStorePromo(picked.path);
      if (!mounted) return;
      setState(() {
        store = data;
        saving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = _asMaps(store['presets']);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Store appearance')),
      body: loading
          ? const FullPageLoader(label: 'Loading store…')
          : error != null
              ? Center(child: Text(error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (store['setup_complete'] != true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final data = await context.read<AppStore>().completeSellerStoreSetup();
                                  if (!mounted) return;
                                  setState(() => store = data);
                                },
                          child: const Text('Mark store setup complete'),
                        ),
                      ),
                    if ((store['cover_url'] as String?)?.isNotEmpty == true)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(imageUrl: store['cover_url'] as String, height: 140, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: (store['logo_url'] as String?)?.isNotEmpty == true
                              ? CachedNetworkImageProvider(store['logo_url'] as String)
                              : null,
                          child: (store['logo_url'] as String?)?.isNotEmpty == true ? null : const Icon(Icons.storefront),
                        ),
                        const SizedBox(width: 12),
                        TextButton(onPressed: () => _pick(true), child: const Text('Change logo')),
                        TextButton(onPressed: () => _pick(false), child: const Text('Change cover')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Store name')),
                    const SizedBox(height: 12),
                    TextField(controller: slogan, decoration: const InputDecoration(labelText: 'Slogan')),
                    const SizedBox(height: 12),
                    TextField(controller: description, maxLines: 4, decoration: const InputDecoration(labelText: 'About the store')),
                    const SizedBox(height: 16),
                    const Text('Hero slideshow', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (_asMaps(store['hero_images']).isNotEmpty)
                      SizedBox(
                        height: 88,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _asMaps(store['hero_images']).length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final img = _asMaps(store['hero_images'])[i];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: img['url'] as String? ?? '',
                                    width: 120,
                                    height: 88,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    onPressed: () => _removeHero(img['path'] as String? ?? ''),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    TextButton.icon(
                      onPressed: saving ? null : _pickHero,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add slideshow photos'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Announcement bar'),
                      value: announcementOn,
                      onChanged: (v) => setState(() => announcementOn = v),
                    ),
                    if (announcementOn)
                      TextField(controller: announcement, decoration: const InputDecoration(labelText: 'Announcement text')),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Promo banner'),
                      value: promoOn,
                      onChanged: (v) => setState(() => promoOn = v),
                    ),
                    if (promoOn) ...[
                      TextField(controller: promo, decoration: const InputDecoration(labelText: 'Promo text')),
                      const SizedBox(height: 8),
                      if ((_asMap(store['promo'])['image_url'] as String?)?.isNotEmpty == true)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: _asMap(store['promo'])['image_url'] as String,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                      TextButton(onPressed: saving ? null : _pickPromo, child: const Text('Change promo image')),
                    ],
                    const SizedBox(height: 8),
                    const Text('Store sections', style: TextStyle(fontWeight: FontWeight.w800)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Featured products'),
                      value: sectionFeatured,
                      onChanged: (v) => setState(() => sectionFeatured = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('About'),
                      value: sectionAbout,
                      onChanged: (v) => setState(() => sectionAbout = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Contact'),
                      value: sectionContact,
                      onChanged: (v) => setState(() => sectionContact = v),
                    ),
                    TextField(controller: facebook, decoration: const InputDecoration(labelText: 'Facebook')),
                    const SizedBox(height: 12),
                    TextField(controller: instagram, decoration: const InputDecoration(labelText: 'Instagram')),
                    const SizedBox(height: 12),
                    TextField(controller: website, decoration: const InputDecoration(labelText: 'Website')),
                    const SizedBox(height: 16),
                    const Text('Theme', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in presets)
                          ChoiceChip(
                            label: Text(preset['label'] as String? ?? ''),
                            selected: store['preset'] == preset['key'],
                            onSelected: (_) => setState(() => store['preset'] = preset['key']),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: saving ? null : () => _save(), child: Text(saving ? 'Saving…' : 'Save draft')),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: saving ? null : () => _save(publish: true), child: const Text('Publish to shop')),
                    if ('${store['slug'] ?? store['store_url'] ?? ''}'.trim().isNotEmpty)
                      TextButton(
                        onPressed: () {
                          final slug = '${store['slug'] ?? ''}'.trim();
                          final url = slug.isNotEmpty
                              ? ApiConfig.storeWebUrl(slug)
                              : '${store['store_url']}';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        child: const Text('Open store on the web'),
                      ),
                  ],
                ),
    );
  }
}

class SellerActivationScreen extends StatefulWidget {
  const SellerActivationScreen({super.key});

  @override
  State<SellerActivationScreen> createState() => _SellerActivationScreenState();
}

class _SellerActivationScreenState extends State<SellerActivationScreen> {
  bool loading = true;
  bool paying = false;
  String? error;
  Map<String, dynamic> account = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerAccount();
      if (!mounted) return;
      setState(() {
        account = data;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _pay() async {
    if (account['has_payment_pin'] != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a payment PIN first in Profile → Payment PIN.')),
      );
      context.push('/profile/payment-pin');
      return;
    }
    final pin = await promptPaymentPin(
      context,
      title: 'Pay seller fee',
      subtitle: 'Confirm with your 4-digit payment PIN',
    );
    if (pin == null) return;
    setState(() => paying = true);
    try {
      final data = await context.read<AppStore>().paySellerActivation(pin);
      if (!mounted) return;
      setState(() {
        account = data;
        paying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] as String? ?? 'Paid.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => paying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activation = _asMap(account['activation']);
    final wallet = _asMap(account['wallet']);
    final fee = (activation['fee_amount'] as num?)?.toDouble() ?? 0;
    final needsPay = activation['needs_payment'] == true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Seller service fee')),
      body: loading
          ? const FullPageLoader(label: 'Loading…')
          : error != null
              ? Center(child: Text(error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      needsPay ? 'Your store is waiting on this yearly fee.' : 'Your store is active.',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fee: ${_money.format(fee)}\nWallet: ${_money.format((wallet['available_balance'] as num?)?.toDouble() ?? 0)}',
                      style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                    if ((activation['paid_until'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text('Paid until ${activation['paid_until']}'),
                    ],
                    const SizedBox(height: 20),
                    if (needsPay)
                      FilledButton(
                        onPressed: paying ? null : _pay,
                        child: Text(paying ? 'Paying…' : 'Pay from wallet'),
                      )
                    else
                      const Text('No payment is due right now.'),
                  ],
                ),
    );
  }
}

class SellerOrderSmsScreen extends StatefulWidget {
  const SellerOrderSmsScreen({super.key});

  @override
  State<SellerOrderSmsScreen> createState() => _SellerOrderSmsScreenState();
}

class _SellerOrderSmsScreenState extends State<SellerOrderSmsScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  final mobile1 = TextEditingController();
  final mobile2 = TextEditingController();
  String? accountMobile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    mobile1.dispose();
    mobile2.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerAccount();
      if (!mounted) return;
      mobile1.text = data['order_sms_mobile_1'] as String? ?? '';
      mobile2.text = data['order_sms_mobile_2'] as String? ?? '';
      setState(() {
        accountMobile = data['account_mobile'] as String?;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final data = await context.read<AppStore>().updateSellerOrderSms(
            mobile1: mobile1.text.trim(),
            mobile2: mobile2.text.trim(),
          );
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] as String? ?? 'Saved.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Order SMS')),
      body: loading
          ? const FullPageLoader(label: 'Loading…')
          : error != null
              ? Center(child: Text(error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      'Both numbers get the same new-order alert. Leave blank to use your account mobile${accountMobile == null ? '' : ' ($accountMobile)'}.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: mobile1,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'First Ghana mobile'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mobile2,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Second Ghana mobile'),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: saving ? null : _save,
                      child: Text(saving ? 'Saving…' : 'Save numbers'),
                    ),
                  ],
                ),
    );
  }
}

class SellerProductAnalyticsScreen extends StatefulWidget {
  const SellerProductAnalyticsScreen({super.key, required this.productId});

  final int productId;

  @override
  State<SellerProductAnalyticsScreen> createState() => _SellerProductAnalyticsScreenState();
}

class _SellerProductAnalyticsScreenState extends State<SellerProductAnalyticsScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> product = {};
  Map<String, dynamic> stats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerProductAnalytics(widget.productId);
      if (!mounted) return;
      setState(() {
        product = _asMap(data['data']);
        stats = _asMap(data['stats']);
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(product['name'] as String? ?? 'Analytics')),
      body: loading
          ? const FullPageLoader(label: 'Loading analytics…')
          : error != null
              ? Center(child: Text(error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _metric('Views', '${stats['views'] ?? 0}'),
                        _metric('Cart adds', '${stats['cart_adds'] ?? 0}'),
                        _metric('Purchases', '${stats['purchases'] ?? 0}'),
                        _metric('Revenue', _money.format((stats['revenue'] as num?)?.toDouble() ?? 0)),
                        _metric('Conversion', '${stats['conversion_rate'] ?? 0}%'),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}

Future<void> printSellerOrderPdf(BuildContext context, int orderItemId) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparing invoice…')));
  try {
    final bytes = await context.read<AppStore>().downloadSellerOrderPdf(orderItemId);
    await Printing.layoutPdf(
      name: 'CityShop-order-$orderItemId',
      onLayout: (_) async => Uint8List.fromList(bytes),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
