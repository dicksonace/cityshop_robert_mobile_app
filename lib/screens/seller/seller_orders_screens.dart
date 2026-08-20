import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import 'seller_hub_screens.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/tab_refresh.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _asMaps(dynamic value) {
  if (value is! List) return [];
  return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

class SellerOrdersTab extends StatefulWidget {
  const SellerOrdersTab({
    super.key,
    this.initialStage = 'all',
    this.onOpenOrder,
  });

  final String initialStage;
  final void Function(int id)? onOpenOrder;

  @override
  State<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends State<SellerOrdersTab> with AutoRefreshTab {
  String stage = 'all';
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> orders = [];
  Map<String, dynamic> counts = {};
  List<Map<String, dynamic>> stages = const [];
  int page = 1;
  int lastPage = 1;
  bool loadingMore = false;

  @override
  int? get tabIndex => 1;

  @override
  void initState() {
    super.initState();
    stage = widget.initialStage;
  }

  @override
  void didUpdateWidget(covariant SellerOrdersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStage != widget.initialStage && widget.initialStage != stage) {
      stage = widget.initialStage;
      _load();
    }
  }

  @override
  Future<void> refreshTabData({required bool background}) => _load(background: background);

  Future<void> _load({bool background = false}) async {
    if (!background) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final data = await context.read<AppStore>().loadSellerOrders(stage: stage, page: 1);
      if (!mounted) return;
      setState(() {
        orders = _asMaps(data['data']);
        counts = _asMap(data['counts']);
        stages = _asMaps(data['stages']);
        final meta = _asMap(data['meta']);
        page = (meta['current_page'] as num?)?.toInt() ?? 1;
        lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (!background || orders.isEmpty) error = e.message;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!background || orders.isEmpty) error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || page >= lastPage) return;
    setState(() => loadingMore = true);
    try {
      final data = await context.read<AppStore>().loadSellerOrders(stage: stage, page: page + 1);
      if (!mounted) return;
      setState(() {
        orders = [...orders, ..._asMaps(data['data'])];
        final meta = _asMap(data['meta']);
        page = (meta['current_page'] as num?)?.toInt() ?? page + 1;
        lastPage = (meta['last_page'] as num?)?.toInt() ?? lastPage;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  void _selectStage(String key) {
    if (key == stage) return;
    setState(() => stage = key);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Orders')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                for (final item in (stages.isEmpty
                    ? const [
                        {'key': 'all', 'label': 'All'},
                        {'key': 'new', 'label': 'New'},
                        {'key': 'processing', 'label': 'Processing'},
                        {'key': 'packing', 'label': 'Packing'},
                        {'key': 'delivery', 'label': 'Delivery'},
                        {'key': 'awaiting', 'label': 'Awaiting'},
                        {'key': 'completed', 'label': 'Completed'},
                        {'key': 'cancelled', 'label': 'Cancelled'},
                      ]
                    : stages))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${item['label']}${(counts[item['key']] as num?) != null ? ' ${(counts[item['key']] as num).toInt()}' : ''}',
                      ),
                      selected: stage == item['key'],
                      onSelected: (_) => _selectStage(item['key'] as String),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: loading && orders.isEmpty
                ? const FullPageLoader(label: 'Loading orders…')
                : error != null && orders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: refreshNow, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: refreshNow,
                        child: orders.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textMuted),
                                  SizedBox(height: 12),
                                  Text(
                                    'No orders in this stage.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              )
                            : NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 240) {
                                    _loadMore();
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                                  itemCount: orders.length + (loadingMore ? 1 : 0),
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, i) {
                                    if (i >= orders.length) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    final item = orders[i];
                                    final id = (item['id'] as num?)?.toInt() ?? 0;
                                    return Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      child: ListTile(
                                        onTap: () {
                                          if (id == 0) return;
                                          if (widget.onOpenOrder != null) {
                                            widget.onOpenOrder!(id);
                                          } else {
                                            context.push('/seller/orders/$id');
                                          }
                                        },
                                        leading: _ProductThumb(url: item['product_image'] as String?),
                                        title: Text(
                                          item['product_name'] as String? ?? 'Order',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                        subtitle: Text(
                                          [
                                            item['order_number'],
                                            item['buyer_name'],
                                            item['status'],
                                          ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
                                        ),
                                        trailing: Text(
                                          _money.format((item['amount'] as num?)?.toDouble() ?? 0),
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}

class SellerOrderDetailScreen extends StatefulWidget {
  const SellerOrderDetailScreen({super.key, required this.orderItemId});

  final int orderItemId;

  @override
  State<SellerOrderDetailScreen> createState() => _SellerOrderDetailScreenState();
}

class _SellerOrderDetailScreenState extends State<SellerOrderDetailScreen> {
  bool loading = true;
  bool busy = false;
  String? error;
  Map<String, dynamic> item = {};
  final vehicleCtrl = TextEditingController();
  final driverCtrl = TextEditingController();
  String? newPackagePath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    vehicleCtrl.dispose();
    driverCtrl.dispose();
    super.dispose();
  }

  void _syncDeliveryFields(Map<String, dynamic> data) {
    vehicleCtrl.text = data['vehicle_number'] as String? ?? '';
    driverCtrl.text = data['driver_phone'] as String? ?? '';
    newPackagePath = null;
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadSellerOrder(widget.orderItemId);
      if (!mounted) return;
      setState(() {
        item = data;
        _syncDeliveryFields(data);
        loading = false;
      });
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

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    setState(() => busy = true);
    try {
      final res = await action();
      if (!mounted) return;
      final data = res['data'];
      if (data is Map) {
        item = Map<String, dynamic>.from(data);
        _syncDeliveryFields(item);
      }
      final message = res['message'] as String?;
      setState(() => busy = false);
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _saveDeliveryDetails() async {
    await _run(() => context.read<AppStore>().updateSellerOrder(
          widget.orderItemId,
          vehicleNumber: vehicleCtrl.text.trim(),
          driverPhone: driverCtrl.text.trim(),
          packageImagePath: newPackagePath,
          saveDeliveryDetails: true,
        ));
  }

  Future<void> _advance(Map<String, dynamic> action) async {
    final status = action['status'] as String?;
    if (status == null) return;
    final needsDelivery = action['needs_delivery_details'] == true;
    await _run(() => context.read<AppStore>().updateSellerOrder(
          widget.orderItemId,
          status: status,
          vehicleNumber: needsDelivery || vehicleCtrl.text.trim().isNotEmpty ? vehicleCtrl.text.trim() : null,
          driverPhone: needsDelivery || driverCtrl.text.trim().isNotEmpty ? driverCtrl.text.trim() : null,
          packageImagePath: newPackagePath,
          saveDeliveryDetails: needsDelivery,
        ));
  }

  bool get _showDeliverySection {
    final status = item['status'] as String? ?? '';
    if (status == 'cancelled' || status == 'refunded' || status == 'pending') return false;
    return true;
  }

  bool get _needsDeliveryHighlight {
    final actions = _asMaps(item['next_actions']);
    return actions.isNotEmpty && actions.first['needs_delivery_details'] == true;
  }

  Future<void> _cancel() async {
    final reasons = _asMaps(item['cancellation_reasons']);
    String code = reasons.isNotEmpty ? reasons.first['code'] as String : 'out_of_stock';
    final noteCtrl = TextEditingController();
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SheetShell(
              action: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel order'),
              ),
              children: [
                const Text('Cancel this order', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: code,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    for (final reason in reasons)
                      DropdownMenuItem(
                        value: reason['code'] as String,
                        child: Text(reason['label'] as String? ?? reason['code'] as String),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setModal(() => code = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Note (required for Other)'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    await _run(() => context.read<AppStore>().rejectSellerOrder(
          widget.orderItemId,
          cancellationCode: code,
          reason: noteCtrl.text,
        ));
  }

  Future<void> _rejectDirect() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (ctx) => SheetShell(
        action: FilledButton(
          onPressed: () {
            if (reasonCtrl.text.trim().length < 5) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('Reject payment'),
        ),
        children: [
          const Text('Reject payment claim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason for the buyer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => context.read<AppStore>().rejectSellerDirectPayment(
          widget.orderItemId,
          reasonCtrl.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final order = _asMap(item['order']);
    final buyer = _asMap(order['buyer']);
    final actions = _asMaps(item['next_actions']);
    final phone = (order['receiver_phone'] as String?) ?? (buyer['mobile'] as String?);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(order['order_number'] as String? ?? 'Order')),
      body: loading
          ? const FullPageLoader(label: 'Loading order…')
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Row(
                      children: [
                        _ProductThumb(
                          url: () {
                            final images = _asMaps(_asMap(item['product'])['images']);
                            return images.isNotEmpty ? images.first['url'] as String? : null;
                          }(),
                          size: 64,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['product_name'] as String? ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('Qty ${(item['quantity'] as num?)?.toInt() ?? 1} · ${_money.format((item['seller_amount'] as num?)?.toDouble() ?? 0)}'),
                              Text((item['status'] as String? ?? '').replaceAll('_', ' '), style: const TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Card(
                      children: [
                        Text(buyer['name'] as String? ?? order['receiver_name'] as String? ?? 'Buyer', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text([
                          order['receiver_name'],
                          phone,
                          [order['city'], order['region']].whereType<String>().where((e) => e.isNotEmpty).join(', '),
                        ].whereType<String>().where((e) => e.isNotEmpty).join('\n')),
                        if ((order['delivery_notes'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(order['delivery_notes'] as String, style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                        if (phone != null && phone.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Call buyer'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      children: [
                        Text('Payment · ${order['payment_channel'] ?? ''} · ${order['payment_status'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Method: ${order['payment_method'] ?? '—'}'),
                        if ((order['direct_payment_reference'] as String?)?.isNotEmpty == true)
                          Text('Reference: ${order['direct_payment_reference']}'),
                        if ((order['direct_payment_proof_url'] as String?)?.isNotEmpty == true)
                          TextButton(
                            onPressed: () => showImageViewer(context, urls: [order['direct_payment_proof_url'] as String]),
                            child: const Text('View payment proof'),
                          ),
                      ],
                    ),
                    if (_showDeliverySection) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _needsDeliveryHighlight ? const Color(0xFFFFF7ED) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _needsDeliveryHighlight ? const Color(0xFFFDBA74) : AppColors.border,
                            width: _needsDeliveryHighlight ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _needsDeliveryHighlight ? 'Delivery details (optional)' : 'Delivery details',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Optional. Add if a driver is delivering for you; leave blank if you bring it yourself. Buyer only sees what you enter.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: vehicleCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Vehicle / car number',
                                hintText: 'e.g. GR 1234-20',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: driverCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Driver phone',
                                hintText: 'e.g. 024 000 0000',
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Package photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            const SizedBox(height: 8),
                            if (newPackagePath != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(newPackagePath!),
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else if ((item['package_image'] as String?)?.isNotEmpty == true)
                              InkWell(
                                onTap: () => showImageViewer(
                                  context,
                                  urls: [ApiConfig.resolveMediaUrl(item['package_image'] as String)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: ApiConfig.resolveMediaUrl(item['package_image'] as String),
                                    width: 120,
                                    height: 120,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final picked = await ImagePicker().pickImage(
                                        source: ImageSource.gallery,
                                        imageQuality: 82,
                                      );
                                      if (picked == null || !mounted) return;
                                      setState(() => newPackagePath = picked.path);
                                    },
                              icon: const Icon(Icons.photo_outlined),
                              label: Text(
                                newPackagePath != null || (item['package_image'] as String?)?.isNotEmpty == true
                                    ? 'Change package photo'
                                    : 'Add package photo',
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: busy ? null : _saveDeliveryDetails,
                                child: Text(busy ? 'Saving…' : 'Save delivery info'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (item['can_confirm_direct_payment'] == true) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: busy ? null : () => _run(() => context.read<AppStore>().confirmSellerDirectPayment(widget.orderItemId)),
                        child: const Text('Confirm buyer payment'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: busy ? null : _rejectDirect,
                        child: const Text('Reject payment claim'),
                      ),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy ? null : () => _advance(actions.first),
                        child: Text(actions.first['label'] as String? ?? 'Update status'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => printSellerOrderPdf(context, widget.orderItemId),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print / save PDF'),
                    ),
                    if (item['can_cancel'] == true) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: busy ? null : _cancel,
                        child: const Text('Cancel order'),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({this.url, this.size = 48});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFFECFDF5),
        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF047857)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
