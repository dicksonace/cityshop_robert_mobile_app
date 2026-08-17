import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _asMaps(dynamic value) {
  if (value is! List) return [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

class SellerPaymentMethodsScreen extends StatefulWidget {
  const SellerPaymentMethodsScreen({super.key});

  @override
  State<SellerPaymentMethodsScreen> createState() => _SellerPaymentMethodsScreenState();
}

class _SellerPaymentMethodsScreenState extends State<SellerPaymentMethodsScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  Map<String, dynamic> profile = {};
  List<Map<String, dynamic>> methods = [];
  List<Map<String, dynamic>> banks = [];
  List<String> networks = const ['MTN', 'Telecel', 'AirtelTigo'];

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
      final data = await context.read<AppStore>().loadSellerPaymentMethods();
      if (!mounted) return;
      setState(() {
        profile = _asMap(data['profile']);
        methods = _asMaps(data['methods']);
        banks = _asMaps(data['banks']);
        final rawNetworks = data['networks'];
        if (rawNetworks is List) {
          networks = rawNetworks.whereType<String>().toList();
        }
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

  Future<void> _saveSettings({
    bool? marketplace,
    bool? direct,
    bool? cash,
  }) async {
    setState(() => saving = true);
    try {
      final data = await context.read<AppStore>().updateSellerPaymentSettings(
            acceptMarketplace: marketplace ?? profile['accept_marketplace_payments'] == true,
            acceptDirect: direct ?? profile['accept_direct_payments'] == true,
            cashOnDelivery: cash ?? profile['cash_on_delivery_enabled'] == true,
          );
      if (!mounted) return;
      setState(() {
        profile = _asMap(data['profile']);
        methods = _asMaps(data['methods']);
        saving = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      await _load();
    }
  }

  Future<void> _addMethod() async {
    var type = 'mobile_money';
    var network = networks.isNotEmpty ? networks.first : 'MTN';
    String? bankId = banks.isNotEmpty ? banks.first['id'] as String? : null;
    final nameCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    final added = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SheetShell(
              action: FilledButton(
                onPressed: () async {
                  try {
                    await context.read<AppStore>().addSellerPaymentMethod(
                          type: type,
                          accountName: nameCtrl.text.trim(),
                          accountNumber: numberCtrl.text.trim(),
                          network: type == 'mobile_money' ? network : null,
                          bankName: type == 'bank' ? bankId : null,
                          isDefault: methods.isEmpty,
                        );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on ApiException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                child: const Text('Save method'),
              ),
              children: [
                const Text('Add payment method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  ],
                  onChanged: (v) {
                    if (v != null) setModal(() => type = v);
                  },
                ),
                const SizedBox(height: 12),
                if (type == 'mobile_money')
                  DropdownButtonFormField<String>(
                    value: network,
                    decoration: const InputDecoration(labelText: 'Network'),
                    items: [
                      for (final item in networks) DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => network = v);
                    },
                  )
                else
                  DropdownButtonFormField<String>(
                    value: bankId,
                    decoration: const InputDecoration(labelText: 'Bank'),
                    items: [
                      for (final bank in banks)
                        DropdownMenuItem(value: bank['id'] as String?, child: Text(bank['label'] as String? ?? '')),
                    ],
                    onChanged: (v) => setModal(() => bankId = v),
                  ),
                const SizedBox(height: 12),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Account name')),
                const SizedBox(height: 12),
                TextField(
                  controller: numberCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: type == 'bank' ? 'Account number' : 'MoMo number'),
                ),
              ],
            );
          },
        );
      },
    );
    if (added == true) await _load();
  }

  Future<void> _delete(int id) async {
    try {
      final data = await context.read<AppStore>().deleteSellerPaymentMethod(id);
      if (!mounted) return;
      setState(() {
        profile = _asMap(data['profile']);
        methods = _asMaps(data['methods']);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = profile['payment_methods_locked'] == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: locked ? null : _addMethod,
        icon: const Icon(Icons.add),
        label: const Text('Add method'),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading payment methods…')
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('CityShop checkout'),
                        subtitle: const Text('Buyers can pay through the marketplace wallet / Paystack.'),
                        value: profile['accept_marketplace_payments'] == true,
                        onChanged: saving ? null : (v) => _saveSettings(marketplace: v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pay to seller'),
                        subtitle: const Text('Buyers send MoMo or bank to your own accounts.'),
                        value: profile['accept_direct_payments'] == true,
                        onChanged: saving ? null : (v) => _saveSettings(direct: v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Cash on delivery'),
                        value: profile['cash_on_delivery_enabled'] == true,
                        onChanged: saving ? null : (v) => _saveSettings(cash: v),
                      ),
                      if (locked) ...[
                        const SizedBox(height: 8),
                        Text(
                          profile['payment_methods_lock_reason'] as String? ?? 'Payment methods are locked by admin.',
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text('Your accounts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 8),
                      if (methods.isEmpty)
                        const Text('Add a MoMo or bank account so buyers can pay you directly.', style: TextStyle(color: AppColors.textSecondary)),
                      ...methods.map((method) {
                        final id = (method['id'] as num?)?.toInt() ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(method['label'] as String? ?? 'Method', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              method['account_name'],
                              if (method['is_default'] == true) 'Default',
                              if (method['is_disabled'] == true) method['disabled_reason'] ?? 'Disabled',
                            ].whereType<String>().where((e) => e.isNotEmpty).join(' · ')),
                            trailing: method['is_disabled'] == true
                                ? null
                                : IconButton(
                                    onPressed: () => _delete(id),
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
