import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../models/models.dart';
import '../../store/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Ghana Card KYC required before storing money in the wallet.
/// Direct Paystack checkout is not blocked.
class KycVerificationScreen extends StatefulWidget {
  const KycVerificationScreen({super.key});

  @override
  State<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends State<KycVerificationScreen> {
  bool loading = true;
  bool saving = false;
  String? error;
  KycInfo kyc = const KycInfo();
  final cardNumber = TextEditingController();
  XFile? front;
  XFile? back;
  XFile? selfie;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    cardNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await context.read<AppStore>().loadKyc();
      if (!mounted) return;
      kyc = data;
      cardNumber.text = data.ghanaCardNumber ?? '';
      setState(() => loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<XFile?> _pickPhoto(String title) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Take $title photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose $title from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return ImagePicker().pickImage(source: source, imageQuality: 82, maxWidth: 2000);
  }

  Future<void> _submit() async {
    if (cardNumber.text.trim().length < 10) {
      _toast('Enter your Ghana Card number');
      return;
    }
    if (front == null && (kyc.frontUrl ?? '').isEmpty) {
      _toast('Add a photo of the front of your Ghana Card');
      return;
    }
    if (back == null && (kyc.backUrl ?? '').isEmpty) {
      _toast('Add a photo of the back of your Ghana Card');
      return;
    }
    if (front == null || back == null) {
      _toast('Take new front and back photos to resubmit.');
      return;
    }
    setState(() => saving = true);
    try {
      await context.read<AppStore>().submitKyc(
            ghanaCardNumber: cardNumber.text.trim(),
            fullName: context.read<AppStore>().user?.name,
            frontPath: front!.path,
            backPath: back!.path,
            selfiePath: selfie?.path,
          );
      if (!mounted) return;
      _toast('Submitted. The system must approve your Ghana Card before you can transact with the CityShop wallet.');
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppStore>().user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Verification & PIN'),
        leading: BackButton(onPressed: () => goBackOr(context, '/shop?tab=account')),
      ),
      body: loading
          ? const FullPageLoader(label: 'Loading verification…')
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _StatusBanner(kyc: kyc),
                    const SizedBox(height: 12),
                    const Text('Ghana Card', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    const Text(
                      'The system must approve your Ghana Card before you can transact with the CityShop wallet.',
                      style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    _GhanaCardPreview(
                      onVerify: kyc.isVerified ? null : () async {
                        final picked = await _pickPhoto('front');
                        if (picked != null) setState(() => front = picked);
                      },
                      verified: kyc.isVerified,
                    ),
                    const SizedBox(height: 16),
                    const Text('Email', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(user?.email ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Security PIN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              SizedBox(height: 4),
                              Text(
                                'Set your PIN to approve payments',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/profile/payment-pin'),
                          child: Text(user?.hasPaymentPin == true ? 'Change PIN' : 'Set PIN'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: cardNumber,
                      enabled: !kyc.isVerified,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Ghana Card number',
                        hintText: 'GHA-123456789-1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _PhotoSlot(label: 'Front', file: front, url: kyc.frontUrl, onTap: kyc.isVerified ? null : () async {
                          final picked = await _pickPhoto('front');
                          if (picked != null) setState(() => front = picked);
                        })),
                        const SizedBox(width: 10),
                        Expanded(child: _PhotoSlot(label: 'Back', file: back, url: kyc.backUrl, onTap: kyc.isVerified ? null : () async {
                          final picked = await _pickPhoto('back');
                          if (picked != null) setState(() => back = picked);
                        })),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _PhotoSlot(
                      label: 'Selfie with card (optional)',
                      file: selfie,
                      url: kyc.selfieUrl,
                      onTap: kyc.isVerified
                          ? null
                          : () async {
                              final picked = await _pickPhoto('selfie');
                              if (picked != null) setState(() => selfie = picked);
                            },
                    ),
                    if (kyc.canSubmit) ...[
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: kyc.isPending ? 'Update Ghana Card' : 'Submit Ghana Card',
                        loading: saving,
                        onPressed: saving ? null : _submit,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.kyc});

  final KycInfo kyc;

  @override
  Widget build(BuildContext context) {
    final (color, fill, title, body) = switch (kyc.status) {
      'approved' => (
          const Color(0xFF047857),
          const Color(0xFFECFDF5),
          'Verified',
          'You can now transact with the CityShop wallet.',
        ),
      'pending' => (
          const Color(0xFFB45309),
          const Color(0xFFFFFBEB),
          'Waiting for approval',
          'The system is reviewing your Ghana Card. You can still buy items with Paystack.',
        ),
      'needs_improvement' => (
          const Color(0xFFB45309),
          const Color(0xFFFFF7ED),
          'Needs improvement',
          kyc.adminNotes ?? 'Please submit clearer Ghana Card photos.',
        ),
      'rejected' => (
          const Color(0xFFB91C1C),
          const Color(0xFFFEF2F2),
          'Not approved',
          kyc.adminNotes ?? 'Submit a new Ghana Card to transact with the CityShop wallet.',
        ),
      _ => (
          AppColors.accent,
          AppColors.ringOrange,
          'Not verified',
          'The system must approve your Ghana Card before you can transact with the CityShop wallet.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: color, height: 1.35, fontSize: 13)),
        ],
      ),
    );
  }
}

class _GhanaCardPreview extends StatelessWidget {
  const _GhanaCardPreview({required this.onVerify, required this.verified});

  final VoidCallback? onVerify;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.85,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF115E59), Color(0xFF134E4A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ECOWAS IDENTITY CARD', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w700)),
                  const Text('REPUBLIC OF GHANA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  const Spacer(),
                  Text(
                    verified ? 'Ghana Card verified' : 'Front and back photos required',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (onVerify != null)
              Center(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF14B8A6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                  onPressed: onVerify,
                  child: const Text('VERIFY GHANA CARD', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.label,
    this.file,
    this.url,
    this.onTap,
    this.tall = false,
  });

  final String label;
  final XFile? file;
  final String? url;
  final VoidCallback? onTap;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.resolveMediaUrl(url);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: tall ? 96 : 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (file != null)
                Image.file(File(file!.path), fit: BoxFit.cover)
              else if (resolved.isNotEmpty)
                CachedNetworkImage(imageUrl: resolved, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: AppColors.accent),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              if (file != null || resolved.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
