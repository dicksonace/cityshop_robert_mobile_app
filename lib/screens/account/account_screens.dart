import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

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

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final cities = store.citiesByRegion[region] ?? <String>[];
            if (city.isEmpty && cities.isNotEmpty) city = cities.first;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(existing == null ? 'Add address' : 'Edit address', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 12),
                    TextField(controller: first, decoration: const InputDecoration(labelText: 'First name')),
                    TextField(controller: last, decoration: const InputDecoration(labelText: 'Last name')),
                    TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                    TextField(controller: line, decoration: const InputDecoration(labelText: 'Address line')),
                    DropdownButtonFormField<String>(
                      initialValue: store.regions.contains(region) ? region : null,
                      decoration: const InputDecoration(labelText: 'Region'),
                      items: store.regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (v) => setModal(() {
                        region = v ?? region;
                        city = (store.citiesByRegion[region] ?? []).firstOrNull ?? '';
                      }),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: cities.contains(city) ? city : null,
                      decoration: const InputDecoration(labelText: 'City'),
                      items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setModal(() => city = v ?? city),
                    ),
                    TextField(controller: digital, decoration: const InputDecoration(labelText: 'Digital address (optional)')),
                    SwitchListTile(
                      value: isDefault,
                      onChanged: (v) => setModal(() => isDefault = v),
                      title: const Text('Default address'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
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

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController mobile;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AppStore>().user;
    name = TextEditingController(text: u?.name ?? '');
    email = TextEditingController(text: u?.email ?? '');
    mobile = TextEditingController(text: u?.mobile ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    mobile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await context.read<AppStore>().updateProfile(
            name: name.text.trim(),
            email: email.text.trim(),
            mobile: mobile.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 10),
          TextField(controller: mobile, decoration: const InputDecoration(labelText: 'Mobile')),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Save changes', loading: saving, onPressed: saving ? null : _save),
        ],
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
        padding: const EdgeInsets.all(16),
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
