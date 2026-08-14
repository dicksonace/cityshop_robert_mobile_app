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

/// Hub: Scan someone else's QR, or show My QR.
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
            'Scan their CityShop QR, or show My QR so they can add you.',
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
            title: 'My QR',
            subtitle: 'Show your QR so others can add you',
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
  late final MobileScannerController _controller;
  bool _handling = false;
  bool _torchOn = false;
  bool _torchUnavailable = false;
  bool _wantTorch = false;
  bool _nightAutoTried = false;
  bool _pausedAfterError = false;
  String? _lastFailedPayload;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
    _controller.addListener(_onScannerState);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScannerState);
    _controller.dispose();
    super.dispose();
  }

  bool get _isNight {
    final hour = TimeOfDay.now().hour;
    return hour >= 18 || hour < 6;
  }

  void _onScannerState() {
    final torch = _controller.value.torchState;
    final on = torch == TorchState.on;
    final unavailable = torch == TorchState.unavailable;
    if (!mounted) return;
    if (on != _torchOn || unavailable != _torchUnavailable) {
      setState(() {
        _torchOn = on;
        _torchUnavailable = unavailable;
      });
    }
    if (!_nightAutoTried && _controller.value.isRunning && !unavailable) {
      _nightAutoTried = true;
      if (_isNight && !on) {
        _wantTorch = true;
        _controller.toggleTorch();
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_handling || _torchUnavailable || !_controller.value.isRunning) return;
    try {
      final turningOn = !_torchOn;
      await _controller.toggleTorch();
      if (mounted) _wantTorch = turningOn;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flashlight is not available on this device')),
      );
    }
  }

  Future<void> _restoreTorchIfNeeded() async {
    if (!_wantTorch || !_controller.value.isRunning) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_wantTorch) return;
    if (_controller.value.torchState == TorchState.off) {
      await _controller.toggleTorch();
    }
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

  void _toastOnce(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  Future<void> _pauseAfterError(String? payload) async {
    _lastFailedPayload = payload?.trim();
    _pausedAfterError = true;
    try {
      await _controller.stop();
    } catch (_) {}
    if (mounted) setState(() => _handling = false);
  }

  Future<void> _resumeScan() async {
    _pausedAfterError = false;
    _lastFailedPayload = null;
    if (!mounted) return;
    setState(() => _handling = false);
    await _controller.start();
    await _restoreTorchIfNeeded();
  }

  Future<void> _runScanFlow(Future<String?> Function() readPayload) async {
    if (_handling || _pausedAfterError) return;
    setState(() => _handling = true);
    HapticFeedback.mediumImpact();
    String? raw;
    try {
      await _controller.stop();
      if (!mounted) return;
      raw = await readPayload();
      if (!mounted) return;
      if (raw == null || raw.trim().isEmpty) {
        _toastOnce('No CityShop QR code found');
        await _pauseAfterError(null);
        return;
      }
      await _resolveAndOpenContact(raw);
    } on ApiException catch (e) {
      if (mounted) _toastOnce(e.message);
      await _pauseAfterError(raw);
    } catch (e) {
      if (mounted) _toastOnce('$e');
      await _pauseAfterError(raw);
    } finally {
      if (mounted && !_pausedAfterError) {
        setState(() => _handling = false);
        await _controller.start();
        await _restoreTorchIfNeeded();
      }
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _pausedAfterError) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((v) => v.trim())
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    if (_lastFailedPayload != null && raw == _lastFailedPayload) return;
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
          Align(
            alignment: const Alignment(0, -0.18),
            child: _TorchToggle(
              on: _torchOn,
              enabled: !_handling && _controller.value.isRunning && !_torchUnavailable,
              onTap: _toggleTorch,
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 118,
            child: _pausedAfterError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Scan paused',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _resumeScan,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        child: const Text(
                          'Scan again',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  )
                : Text(
                    _handling
                        ? 'Reading code…'
                        : (_torchOn
                            ? 'Light on · scan QR / barcode'
                            : 'Align the CityShop QR inside the frame'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _bottomAction(
                    icon: Icons.qr_code_2_rounded,
                    label: 'My QR',
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

class _TorchToggle extends StatelessWidget {
  const _TorchToggle({
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: on ? const Color(0xFFFFF7ED) : Colors.white.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(
                on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                color: on ? AppColors.accent : Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          on ? 'Tap to turn off' : 'Tap to turn on',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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

  String get _shareInviteText {
    if (_amount != null) {
      return 'Scan my QR to send me ${_money.format(_amount)}.';
    }
    return 'Scan my CityShop QR to add me, pay, or chat.';
  }

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
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow photo access to save your QR')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/CityShop_Pay_${_safeName}_$stamp.png');
      await file.writeAsBytes(bytes, flush: true);
      await Gal.putImage(file.path, album: 'CityShop');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Photos')),
      );
      await Gal.open();
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
          subject: 'Add me on CityShop',
          text: _shareInviteText,
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
      backgroundColor: const Color(0xFFFFF7ED),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('My QR'),
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: AppColors.accent,
                              padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                              child: Column(
                                children: [
                                  const Text(
                                    'Recommended to use',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'CityShop Pay',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFACC15),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Wallet  ·  Transfer  ·  Chat',
                                      style: TextStyle(
                                        color: Color(0xFF111827),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.12),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        if (_payload != null)
                                          SizedBox(
                                            width: 236,
                                            height: 236,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                QrImageView(
                                                  data: _payload!,
                                                  version: QrVersions.auto,
                                                  size: 236,
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
                                                _profileBadge(size: 54),
                                              ],
                                            ),
                                          ),
                                        const SizedBox(height: 14),
                                        Text(
                                          _name ?? 'CityShop',
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 17,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _roleBadge(),
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
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                ],
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              color: Colors.white,
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(
                                      'assets/branding/cityshop_logo.png',
                                      height: 32,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 32,
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: AppColors.accent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Text(
                                          'C',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'CityShop Pay',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                ],
                              ),
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
                            icon: Icons.payments_outlined,
                            label: 'Specify Amount',
                            busy: _saving || _applyingAmount,
                            onTap: () async => _openAmountEditor(),
                          ),
                        ),
                        Expanded(
                          child: _CardAction(
                            icon: Icons.save_alt_rounded,
                            label: 'Save Picture',
                            busy: _saving,
                            onTap: _saveToAlbum,
                          ),
                        ),
                        Expanded(
                          child: _CardAction(
                            icon: Icons.ios_share_rounded,
                            label: 'Share',
                            busy: _saving,
                            onTap: _shareCard,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'They can add you by scanning this QR.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if (_editingAmount) ...[
                    const SizedBox(height: 14),
                    // Solid amount block — no floating dialog over the QR.
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
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
                            ),
                    ),
                    ],
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
                        if (reason.isNotEmpty) ...[
                          Text(
                            reason,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (fixed != null && fixed > 0) const SizedBox(height: 6),
                        ],
                        if (fixed != null && fixed > 0)
                          Text(
                            _money.format(fixed),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: AppColors.accent,
                            ),
                          ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Transfer money or chat me',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _opening ? null : _openTransfer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('Transfer money'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _opening ? null : _openChat,
                      icon: _opening
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                      label: Text(_opening ? 'Opening…' : 'Chat me'),
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
