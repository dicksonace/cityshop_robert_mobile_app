import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/payment_pin_sheet.dart';
import '../../widgets/payment_success_screen.dart';
import '../../widgets/wallet_transfer_pad.dart';

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
            'Scan a CityShop QR to send money or add the person, or show your own namecard so they can scan you.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          _HubTile(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scan to pay or add friend',
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
            title: 'My namecard',
            subtitle: 'Show your code so others can pay you or add you',
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

  /// Lands on the contact screen rather than the keypad: a scan can mean
  /// "pay them" or "add them", and only the scanner knows which.
  Future<void> _resolveAndOpenContact(String raw) async {
    final payload = raw.trim();
    if (payload.isEmpty) return;
    final store = context.read<AppStore>();
    final resolved = await store.resolveQrPayment(payload);
    if (!mounted) return;
    await context.push('/qr/contact', extra: {
      'payload': payload,
      'resolved': resolved,
    });
  }

  Future<void> _runScanFlow(Future<String?> Function() readPayload) async {
    if (_handling) return;
    setState(() => _handling = true);
    HapticFeedback.mediumImpact();
    try {
      await _controller.stop();
      if (!mounted) return;
      final raw = await readPayload();
      if (!mounted) return;
      if (raw == null || raw.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No CityShop QR code found'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      await _resolveAndOpenContact(raw);
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((v) => v.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    await _runScanFlow(() async => raw);
  }

  Future<void> _pickFromAlbum() async {
    if (_handling) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (file == null || !mounted) return;

    await _runScanFlow(() async {
      final capture = await _controller.analyzeImage(file.path);
      return capture?.barcodes
              .map((b) => b.rawValue)
              .whereType<String>()
              .map((v) => v.trim())
              .firstWhere((v) => v.isNotEmpty, orElse: () => '') ??
          '';
    });
  }

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.18),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan'),
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
            bottom: 118,
            child: Text(
              _handling ? 'Reading code…' : 'Align the CityShop QR inside the frame',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            left: 36,
            right: 36,
            bottom: 36,
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _bottomAction(
                    icon: Icons.qr_code_2_rounded,
                    label: 'My namecard',
                    onTap: _handling ? null : () => context.push('/qr/receive'),
                  ),
                  _bottomAction(
                    icon: Icons.photo_library_outlined,
                    label: 'Album',
                    onTap: _handling ? null : _pickFromAlbum,
                  ),
                ],
              ),
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
  bool _saving = false;
  String? _error;
  String? _payload;
  String? _name;
  String? _avatar;
  String? _role;
  double? _amount;
  String? _reason;
  bool _editingAmount = false;
  bool _applyingAmount = false;
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _qrCardKey = GlobalKey();
  final _amountFocus = FocusNode();
  final _reasonFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _amountFocus.dispose();
    _reasonFocus.dispose();
    super.dispose();
  }

  String get _roleLabel {
    final role = (_role ?? '').toLowerCase().trim();
    if (role == 'seller') return 'Seller';
    if (role == 'admin') return 'Admin';
    return 'Buyer';
  }

  Future<void> _load({double? amount, String? reason}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = context.read<AppStore>();
      final data = await store.loadQrReceiveCode(amount: amount, reason: reason);
      if (!mounted) return;
      setState(() {
        _payload = data['payload'] as String?;
        final user = data['user'];
        if (user is Map) {
          _name = user['name'] as String? ?? store.user?.name;
          _avatar = user['avatar'] as String? ?? store.user?.avatar;
          _role = user['role'] as String? ?? store.user?.role;
        } else {
          _name = store.user?.name;
          _avatar = store.user?.avatar;
          _role = store.user?.role;
        }
        _amount = (data['amount'] as num?)?.toDouble();
        _reason = (data['reason'] as String?)?.trim();
        if (_reason != null && _reason!.isEmpty) _reason = null;
        if (_amount != null) {
          _amountCtrl.text = _amount!.toStringAsFixed(2);
        } else {
          _amountCtrl.clear();
        }
        _reasonCtrl.text = _reason ?? '';
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
    final reason = _reasonCtrl.text.trim();
    if (raw.isEmpty) {
      // Reason alone is allowed only with an amount — otherwise clear both.
      setState(() => _applyingAmount = true);
      try {
        await _load();
        if (mounted) setState(() => _editingAmount = false);
      } finally {
        if (mounted) setState(() => _applyingAmount = false);
      }
      return;
    }
    final amount = double.tryParse(raw);
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least GH₵1')),
      );
      return;
    }
    if (reason.length > 80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reason must be 80 characters or less')),
      );
      return;
    }
    setState(() => _applyingAmount = true);
    try {
      await _load(amount: amount, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        setState(() => _editingAmount = false);
        _amountFocus.unfocus();
        _reasonFocus.unfocus();
      }
    } finally {
      if (mounted) setState(() => _applyingAmount = false);
    }
  }

  void _openAmountEditor() {
    _amountCtrl.text = _amount?.toStringAsFixed(2) ?? '';
    _reasonCtrl.text = _reason ?? '';
    setState(() => _editingAmount = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  Future<void> _clearAmount() async {
    _amountCtrl.clear();
    _reasonCtrl.clear();
    setState(() => _applyingAmount = true);
    try {
      await _load();
      if (mounted) {
        setState(() => _editingAmount = false);
        _amountFocus.unfocus();
        _reasonFocus.unfocus();
      }
    } finally {
      if (mounted) setState(() => _applyingAmount = false);
    }
  }

  String get _safeName => (_name ?? 'cityshop').replaceAll(RegExp(r'[^\w\-]+'), '_');

  /// Paints the namecard to a PNG. The frame has to settle first or the
  /// RepaintBoundary can capture mid-layout.
  Future<Uint8List> _captureCard() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final boundary = _qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('namecard not ready yet');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('could not encode the image');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _runCardAction(Future<void> Function(Uint8List bytes) action) async {
    if (_payload == null || _saving) return;
    setState(() => _saving = true);
    try {
      await action(await _captureCard());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save your namecard: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveToAlbum() {
    return _runCardAction((bytes) async {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow photo access to save your namecard')),
          );
        }
        return;
      }
      await Gal.putImageBytes(bytes, name: 'cityshop_namecard_$_safeName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your photos')),
        );
      }
    });
  }

  Future<void> _shareCard() {
    return _runCardAction((bytes) async {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/cityshop_namecard_$_safeName.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png', name: 'cityshop_namecard.png')],
          subject: 'My CityShop namecard',
          text: _amount != null
              ? 'Scan my CityShop QR to send me ${_money.format(_amount)}'
              : 'Scan my CityShop QR to send me money or add me on CityShop',
          sharePositionOrigin: origin,
        ),
      );
    });
  }

  Widget _profileBadge({double size = 56}) {
    final name = (_name ?? 'C').trim();
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final url = ApiConfig.resolveMediaUrl(_avatar);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorWidget: (context, url, error) => _avatarFallback(letter, size),
                placeholder: (context, url) => _avatarFallback(letter, size),
              )
            : _avatarFallback(letter, size),
      ),
    );
  }

  Widget _avatarFallback(String letter, double size) {
    return ColoredBox(
      color: AppColors.accent,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }

  Widget _roleBadge() {
    final seller = _roleLabel == 'Seller';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: seller ? const Color(0xFFEEF6FF) : const Color(0xFFFFF4EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _roleLabel,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: seller ? const Color(0xFF1D4ED8) : AppColors.accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My namecard'),
        actions: [
          IconButton(
            tooltip: 'Refresh code',
            onPressed: _loading ? null : () => _load(amount: _amount, reason: _reason),
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
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    28 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    RepaintBoundary(
                      key: _qrCardKey,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _profileBadge(size: 46),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _name ?? 'CityShop',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _roleBadge(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Scan this QR code to send me money or add me on CityShop',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                            ),
                            if (_amount != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _money.format(_amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  color: AppColors.accent,
                                ),
                              ),
                              if ((_reason ?? '').isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _reason!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 16),
                            if (_payload != null)
                              SizedBox(
                                width: 240,
                                height: 240,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    QrImageView(
                                      data: _payload!,
                                      version: QrVersions.auto,
                                      size: 240,
                                      // High ECC so scanners still read with avatar over the middle.
                                      errorCorrectionLevel: QrErrorCorrectLevel.H,
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
                                    _profileBadge(size: 58),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.verified_user_outlined, size: 18, color: AppColors.emerald),
                                SizedBox(width: 6),
                                Text(
                                  'Security guaranteed',
                                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _CardAction(
                            icon: Icons.ios_share_rounded,
                            label: 'Share',
                            busy: _saving,
                            onTap: _shareCard,
                          ),
                        ),
                        Expanded(
                          child: _CardAction(
                            icon: Icons.image_outlined,
                            label: 'Save to album',
                            busy: _saving,
                            onTap: _saveToAlbum,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Solid amount block — no floating dialog over the QR.
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _editingAmount
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Request amount',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Leave amount empty for an open QR. Reason is optional.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _amountCtrl,
                                  focusNode: _amountFocus,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _reasonFocus.requestFocus(),
                                  decoration: const InputDecoration(
                                    prefixText: 'GH₵ ',
                                    hintText: '0.00',
                                    labelText: 'Amount',
                                    filled: true,
                                    fillColor: Color(0xFFF8FAFC),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _reasonCtrl,
                                  focusNode: _reasonFocus,
                                  maxLength: 80,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _setAmount(),
                                  decoration: const InputDecoration(
                                    labelText: 'Reason for request',
                                    hintText: 'e.g. Lunch money, market stall fee',
                                    filled: true,
                                    fillColor: Color(0xFFF8FAFC),
                                    counterText: '',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: _applyingAmount ? null : () {
                                        setState(() => _editingAmount = false);
                                        _amountFocus.unfocus();
                                        _reasonFocus.unfocus();
                                      },
                                      child: const Text('Cancel'),
                                    ),
                                    if (_amount != null || (_reason ?? '').isNotEmpty)
                                      TextButton(
                                        onPressed: _applyingAmount ? null : _clearAmount,
                                        child: const Text('Clear'),
                                      ),
                                    const Spacer(),
                                    SizedBox(
                                      height: 40,
                                      child: ElevatedButton(
                                        onPressed: _applyingAmount ? null : _setAmount,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: Text(_applyingAmount ? 'Updating…' : 'Update QR'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : InkWell(
                              onTap: _saving ? null : _openAmountEditor,
                              borderRadius: BorderRadius.circular(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.ringOrange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.payments_outlined, color: AppColors.accent, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _amount == null ? 'Request a fixed amount' : 'Requested amount',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _amount == null
                                              ? 'Optional — set amount and reason'
                                              : (_reason == null || _reason!.isEmpty)
                                                  ? _money.format(_amount)
                                                  : '${_money.format(_amount)} · $_reason',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _amount == null ? AppColors.textSecondary : AppColors.accent,
                                            fontWeight: _amount == null ? FontWeight.w400 : FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

/// Icon-over-label action, the shape the namecard buttons take.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: AppColors.accent, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a scanned namecard lands: who they are, then the two things you can
/// do with them. Sending money and starting a chat both need the same person,
/// so the scan resolves once and this screen branches.
class QrContactScreen extends StatefulWidget {
  const QrContactScreen({super.key, required this.payload, required this.resolved});

  final String payload;
  final Map<String, dynamic> resolved;

  @override
  State<QrContactScreen> createState() => _QrContactScreenState();
}

class _QrContactScreenState extends State<QrContactScreen> {
  bool _opening = false;

  Map<String, dynamic> get _user {
    final u = widget.resolved['user'];
    return u is Map ? Map<String, dynamic>.from(u) : {};
  }

  String get _name => _user['name'] as String? ?? 'CityShop user';

  String get _roleLabel {
    final role = (_user['role'] as String? ?? '').toLowerCase().trim();
    if (role == 'seller') return 'Seller';
    if (role == 'admin') return 'Admin';
    return 'Buyer';
  }

  Future<void> _openChat() async {
    final id = (_user['id'] as num?)?.toInt();
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This QR code has no account attached')),
      );
      return;
    }
    setState(() => _opening = true);
    try {
      final opened = await context.read<AppStore>().openConversation(
            sellerId: id,
            userId: id,
          );
      if (!mounted) return;
      context.pushReplacement('/messages/${opened.conversation.id}');
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
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openTransfer() {
    context.push('/qr/pay', extra: {
      'payload': widget.payload,
      'resolved': widget.resolved,
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = (_user['mobile'] as String? ?? '').trim();
    final avatar = ApiConfig.resolveMediaUrl(_user['avatar'] as String?);
    final letter = _name.trim().isNotEmpty ? _name.trim()[0].toUpperCase() : 'C';
    final fixed = (widget.resolved['amount'] as num?)?.toDouble();
    final reason = (widget.resolved['reason'] as String? ?? '').trim();
    final seller = _roleLabel == 'Seller';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('CityShop contact')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: avatar.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: avatar,
                              fit: BoxFit.cover,
                              width: 88,
                              height: 88,
                              errorWidget: (_, __, ___) => _initial(letter),
                              placeholder: (_, __) => _initial(letter),
                            )
                          : _initial(letter),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: seller ? const Color(0xFFEEF6FF) : const Color(0xFFFFF4EC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _roleLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: seller ? const Color(0xFF1D4ED8) : AppColors.accent,
                      ),
                    ),
                  ),
                ),
                if (mobile.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    mobile,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
                if ((fixed != null && fixed > 0) || reason.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.ringOrange,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          fixed != null && fixed > 0 ? 'They are asking for' : 'Reason for request',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (fixed != null && fixed > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            _money.format(fixed),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                        if (reason.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            reason,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _opening ? null : _openChat,
                        icon: _opening
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                        label: Text(_opening ? 'Opening…' : 'Chat'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _opening ? null : _openTransfer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                        label: const Text('Transfer'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initial(String letter) {
    return ColoredBox(
      color: AppColors.accent,
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 34,
          ),
        ),
      ),
    );
  }
}

class QrPayScreen extends StatelessWidget {
  const QrPayScreen({super.key, required this.payload, required this.resolved});

  final String payload;
  final Map<String, dynamic> resolved;

  Map<String, dynamic> get _user {
    final u = resolved['user'];
    return u is Map ? Map<String, dynamic>.from(u) : {};
  }

  @override
  Widget build(BuildContext context) {
    final name = _user['name'] as String? ?? 'CityShop user';
    final mobile = _user['mobile'] as String?;
    final avatar = _user['avatar'] as String?;
    final fixed = (resolved['amount'] as num?)?.toDouble();
    final lockedAmount = fixed != null && fixed > 0 ? fixed : null;
    final reason = (resolved['reason'] as String? ?? '').trim();

    return WalletTransferPad(
      recipientName: name,
      recipientMobile: mobile,
      recipientAvatar: avatar,
      lockedAmount: lockedAmount,
      initialNote: reason.isEmpty ? null : reason,
      actionLabel: 'Transfer',
      onBack: () => context.pop(),
      onSubmit: (amount, note) async {
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
          subtitle: 'Pay ${_money.format(amount)} to $name',
        );
        if (pin == null || !context.mounted) return;

        try {
          final result = await store.payWithQr(
            payload: payload,
            amount: amount,
            paymentPin: pin,
            note: note,
          );
          if (!context.mounted) return;
          final ref = result['reference'] as String? ?? '';
          // Full-page success only — no "Open chat" shortcut (that button was
          // marked to remove). Transfer still lands in chat on the backend.
          await showPaymentSuccess(
            context,
            amount: amount,
            recipientName: name,
            reference: ref,
            note: note,
          );
          if (!context.mounted) return;
          context.go('/shop?tab=wallet');
        } on ApiException catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
          );
        }
      },
    );
  }
}
