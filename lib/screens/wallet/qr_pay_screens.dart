import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/api_client.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';

final _money = NumberFormat.currency(symbol: 'GH₵', decimalDigits: 2);

/// Hub: Scan someone else's code, or show My QR to receive.
class QrPayHubScreen extends StatelessWidget {
  const QrPayHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppStore>().user;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pay / Receive')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const Text(
            'Scan a CityShop QR to pay from your wallet, or show your code so someone can pay you.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          _HubTile(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scan to pay',
            subtitle: 'Point your camera at their CityShop QR',
            onTap: () {
              if (user == null) {
                context.push('/login');
                return;
              }
              context.push('/qr/scan');
            },
          ),
          const SizedBox(height: 10),
          _HubTile(
            icon: Icons.qr_code_2_rounded,
            title: 'My QR · Receive',
            subtitle: 'Show this code for others to scan and pay you',
            onTap: () {
              if (user == null) {
                context.push('/login');
                return;
              }
              context.push('/qr/receive');
            },
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.ringOrange,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((v) => v.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    setState(() => _handling = true);
    HapticFeedback.mediumImpact();
    try {
      await _controller.stop();
      if (!mounted) return;
      final store = context.read<AppStore>();
      final resolved = await store.resolveQrPayment(raw);
      if (!mounted) return;
      await context.push('/qr/pay', extra: {
        'payload': raw,
        'resolved': resolved,
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _handling = false);
        await _controller.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan to pay'),
        actions: [
          TextButton(
            onPressed: () => context.push('/qr/receive'),
            child: const Text('My QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanFramePainter(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              _handling ? 'Reading code…' : 'Align the CityShop QR inside the frame',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final hole = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.72,
      height: size.width * 0.72,
    );
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black.withValues(alpha: 0.55));

    final border = Paint()
      ..color = const Color(0xFF22C55E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18)), border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class QrReceiveScreen extends StatefulWidget {
  const QrReceiveScreen({super.key});

  @override
  State<QrReceiveScreen> createState() => _QrReceiveScreenState();
}

class _QrReceiveScreenState extends State<QrReceiveScreen> {
  bool _loading = true;
  String? _error;
  String? _payload;
  String? _name;
  double? _amount;
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({double? amount}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<AppStore>().loadQrReceiveCode(amount: amount);
      if (!mounted) return;
      setState(() {
        _payload = data['payload'] as String?;
        final user = data['user'];
        _name = user is Map ? user['name'] as String? : null;
        _amount = (data['amount'] as num?)?.toDouble();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _setAmount() async {
    final raw = _amountCtrl.text.trim();
    if (raw.isEmpty) {
      await _load();
      return;
    }
    final amount = double.tryParse(raw);
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least GH₵1')),
      );
      return;
    }
    await _load(amount: amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Receive'),
        actions: [
          IconButton(
            tooltip: 'Refresh code',
            onPressed: _loading ? null : () => _load(amount: _amount),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const FullPageLoader(label: 'Preparing your QR…')
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.verified_user_outlined, size: 18, color: AppColors.emerald),
                              SizedBox(width: 6),
                              Text('Security guaranteed', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _name ?? 'CityShop',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                          if (_amount != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _money.format(_amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_payload != null)
                            QrImageView(
                              data: _payload!,
                              version: QrVersions.auto,
                              size: 240,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Color(0xFF111827),
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF111827),
                              ),
                            ),
                          const SizedBox(height: 12),
                          const Text(
                            'Ask them to open CityShop → Scan',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Specify amount (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              hintText: 'Leave empty for open amount',
                              prefixText: 'GH₵ ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _setAmount,
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        _amountCtrl.clear();
                        _load();
                      },
                      child: const Text('Clear fixed amount'),
                    ),
                  ],
                ),
    );
  }
}

class QrPayScreen extends StatefulWidget {
  const QrPayScreen({super.key, required this.payload, required this.resolved});

  final String payload;
  final Map<String, dynamic> resolved;

  @override
  State<QrPayScreen> createState() => _QrPayScreenState();
}

class _QrPayScreenState extends State<QrPayScreen> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  bool _paying = false;
  bool _lockedAmount = false;

  @override
  void initState() {
    super.initState();
    final fixed = (widget.resolved['amount'] as num?)?.toDouble();
    _lockedAmount = fixed != null && fixed > 0;
    _amount = TextEditingController(
      text: _lockedAmount ? fixed!.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _user {
    final u = widget.resolved['user'];
    return u is Map ? Map<String, dynamic>.from(u) : {};
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least GH₵1')),
      );
      return;
    }

    final store = context.read<AppStore>();
    if (!(store.user?.hasPaymentPin ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a payment PIN in Profile first')),
      );
      return;
    }

    final pin = await promptPaymentPin(
      context,
      title: 'Confirm QR payment',
      subtitle: 'Pay ${_money.format(amount)} to ${_user['name'] ?? 'recipient'}',
    );
    if (pin == null || !mounted) return;

    setState(() => _paying = true);
    try {
      final result = await store.payWithQr(
        payload: widget.payload,
        amount: amount,
        paymentPin: pin,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      final ref = result['reference'] as String? ?? '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Payment sent'),
          content: Text('You paid ${_money.format(amount)}.\nRef: $ref'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
      if (!mounted) return;
      context.go('/shop?tab=wallet');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _user['name'] as String? ?? 'CityShop user';
    final mobile = _user['mobile'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Pay')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.accent,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      if (mobile != null && mobile.isNotEmpty)
                        Text(mobile, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Amount', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _amount,
            enabled: !_lockedAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: 'GH₵ '),
          ),
          const SizedBox(height: 14),
          const Text('Note (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            maxLength: 120,
            decoration: const InputDecoration(hintText: 'What is this for?'),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Pay now',
            loading: _paying,
            onPressed: _pay,
          ),
        ],
      ),
    );
  }
}
