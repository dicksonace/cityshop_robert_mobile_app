import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/ghana_location_fields.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool loading = true;
  String? error;

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
      await context.read<AppStore>().loadWishlist();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: !store.isLoggedIn
          ? Center(
              child: ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login'),
              ),
            )
          : loading
              ? const FullPageLoader(label: 'Loading wishlist…')
              : error != null
                  ? Center(child: Text(error!))
                  : store.wishlist.isEmpty
                      ? const Center(child: Text('No saved products yet'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: store.wishlist.length,
                          itemBuilder: (context, index) {
                            final item = store.wishlist[index];
                            final p = item.product;
                            final image = p.primaryImageUrl;
                            return InkWell(
                              onTap: () => context.push('/products/${p.slug}'),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: image != null
                                          ? CachedNetworkImage(imageUrl: image, fit: BoxFit.cover)
                                          : const ColoredBox(color: Color(0xFFF8FAFC), child: Icon(Icons.image)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                          Text(_money.format(p.effectivePrice), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
    );
  }
}

class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  bool loading = true;
  String? error;
  final _busy = <int>{};

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
      await context.read<AppStore>().loadFollowing();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _unfollow(FollowedSeller seller) async {
    setState(() => _busy.add(seller.sellerId));
    try {
      await context.read<AppStore>().toggleFollowSeller(seller.sellerId);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(seller.sellerId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Following')),
      body: !store.isLoggedIn
          ? Center(
              child: ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Login'),
              ),
            )
          : loading
              ? const FullPageLoader(label: 'Loading following…')
              : error != null
                  ? Center(child: Text(error!))
                  : store.following.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'You are not following any sellers yet.\nOpen a product and tap Follow this seller.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.accent,
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                            itemCount: store.following.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = store.following[index];
                              final photo = ApiConfig.resolveMediaUrl(item.shopPhoto);
                              final letter = item.storeName.trim().isNotEmpty
                                  ? item.storeName.trim()[0].toUpperCase()
                                  : 'S';
                              final busy = _busy.contains(item.sellerId);
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: item.storeSlug == null || item.storeSlug!.isEmpty
                                      ? null
                                      : () => context.push('/stores/${item.storeSlug}'),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: AppColors.ringOrange,
                                          backgroundImage: photo.isNotEmpty
                                              ? CachedNetworkImageProvider(photo)
                                              : null,
                                          child: photo.isEmpty
                                              ? Text(
                                                  letter,
                                                  style: const TextStyle(
                                                    color: AppColors.accent,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.storeName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                [
                                                  if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
                                                  if (item.totalSales != null) '${item.totalSales} sales',
                                                  if (item.followerCount > 0) '${item.followerCount} followers',
                                                ].where((e) => e.isNotEmpty).join(' · '),
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: busy ? null : () => _unfollow(item),
                                          child: busy
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Unfollow'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
    );
  }
}

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  bool loading = true;
  String? error;

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
      await context.read<AppStore>().loadAddresses();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _edit([BuyerAddress? existing]) async {
    final store = context.read<AppStore>();
    final first = TextEditingController(text: existing?.firstName ?? '');
    final last = TextEditingController(text: existing?.lastName ?? '');
    final phone = TextEditingController(text: existing?.phone ?? store.user?.mobile ?? '');
    final line = TextEditingController(text: existing?.addressLine ?? '');
    final digital = TextEditingController(text: existing?.digitalAddress ?? '');
    String region = existing?.region ?? (store.regions.isNotEmpty ? store.regions.first : 'Greater Accra');
    String city = existing?.city ?? '';
    bool isDefault = existing?.isDefault ?? false;

    final saved = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final cityOptions = store.citiesByRegion[region] ?? ghanaCitiesForRegion(region);
            if (city.isEmpty && cityOptions.isNotEmpty && cityOptions.first != kOtherCity) {
              city = cityOptions.first;
            }
            return SheetShell(
              action: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              children: [
                Text(
                  existing == null ? 'Add address' : 'Edit address',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 12),
                TextField(controller: first, decoration: const InputDecoration(labelText: 'First name')),
                TextField(controller: last, decoration: const InputDecoration(labelText: 'Last name')),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                TextField(controller: line, decoration: const InputDecoration(labelText: 'Address line')),
                GhanaLocationFields(
                  region: region,
                  city: city,
                  onRegionChanged: (value) => setModal(() {
                    region = value;
                    city = (store.citiesByRegion[value] ?? ghanaCitiesForRegion(value)).firstOrNull ?? '';
                  }),
                  onCityChanged: (value) => setModal(() => city = value),
                ),
                TextField(controller: digital, decoration: const InputDecoration(labelText: 'Digital address (optional)')),
                SwitchListTile(
                  value: isDefault,
                  onChanged: (v) => setModal(() => isDefault = v),
                  title: const Text('Default address'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;
    try {
      await store.saveAddress({
        'first_name': first.text.trim(),
        'last_name': last.text.trim(),
        'phone': phone.text.trim(),
        'address_line': line.text.trim(),
        'region': region,
        'city': city,
        'digital_address': digital.text.trim(),
        'is_default': isDefault,
      }, id: existing?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address saved')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addresses'),
        actions: [
          IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add)),
        ],
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading addresses…')
          : error != null
              ? Center(child: Text(error!))
              : store.addresses.isEmpty
                  ? Center(
                      child: ElevatedButton(onPressed: () => _edit(), child: const Text('Add address')),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: store.addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final a = store.addresses[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: a.isDefault ? AppColors.accent : AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(a.fullName, style: const TextStyle(fontWeight: FontWeight.w800))),
                                  if (a.isDefault)
                                    const Text('DEFAULT', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w800)),
                                ],
                              ),
                              Text('${a.addressLine}, ${a.city}, ${a.region}'),
                              Text(a.phone),
                              Row(
                                children: [
                                  TextButton(onPressed: () => _edit(a), child: const Text('Edit')),
                                  if (!a.isDefault)
                                    TextButton(
                                      onPressed: () => store.setDefaultAddress(a.id),
                                      child: const Text('Set default'),
                                    ),
                                  TextButton(
                                    onPressed: () => store.deleteAddress(a.id),
                                    child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}

class ProfileEditScreen extends StatelessWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppStore>().user;
    final name = user?.name ?? '';
    final email = user?.email ?? '';
    final mobile = user?.mobile ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Center(
            child: Column(
              children: [
                BuyerProfileAvatar(
                  name: name,
                  avatar: user?.avatar,
                  radius: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  name.isEmpty ? 'CityShop user' : name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap the photo to update your picture',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _LockedProfileField(label: 'Name', value: name.isEmpty ? '—' : name),
          const SizedBox(height: 10),
          _LockedProfileField(label: 'Email', value: email.isEmpty ? '—' : email),
          const SizedBox(height: 10),
          _LockedProfileField(label: 'Mobile', value: mobile.isEmpty ? '—' : mobile),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Text(
              'Name, email, and mobile are locked so someone who opens your phone cannot change your account details. Contact CityShop support if you need them updated.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedProfileField extends StatelessWidget {
  const _LockedProfileField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool saving = false;
  bool obscureCurrent = true;
  bool obscureNext = true;
  bool obscureConfirm = true;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await context.read<AppStore>().changePassword(
            currentPassword: current.text,
            password: next.text,
            passwordConfirmation: confirm.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  InputDecoration _passDecoration(String label, bool obscure, VoidCallback toggle) {
    return InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: ListView(
        // Keep Update password clear of the system navigation bar.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          TextField(
            controller: current,
            obscureText: obscureCurrent,
            decoration: _passDecoration(
              'Current password',
              obscureCurrent,
              () => setState(() => obscureCurrent = !obscureCurrent),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: next,
            obscureText: obscureNext,
            decoration: _passDecoration(
              'New password',
              obscureNext,
              () => setState(() => obscureNext = !obscureNext),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: confirm,
            obscureText: obscureConfirm,
            decoration: _passDecoration(
              'Confirm password',
              obscureConfirm,
              () => setState(() => obscureConfirm = !obscureConfirm),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Update password', loading: saving, onPressed: saving ? null : _save),
        ],
      ),
    );
  }
}
