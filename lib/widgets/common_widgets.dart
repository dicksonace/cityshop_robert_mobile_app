import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../store/app_store.dart';
import '../theme/app_theme.dart';

/// Steps back a page, falling back to [fallback] when the stack is empty.
///
/// Screens reached with `context.go` (checkout -> direct pay -> order detail)
/// replace the stack, so there is nothing for Navigator to pop and the user is
/// left stranded without the fallback.
void goBackOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Buyer's profile photo with optional camera / gallery upload.
class BuyerProfileAvatar extends StatefulWidget {
  const BuyerProfileAvatar({
    super.key,
    required this.name,
    this.avatar,
    this.radius = 28,
    this.editable = true,
    this.showCameraBadge = true,
  });

  final String name;
  final String? avatar;
  final double radius;
  final bool editable;
  final bool showCameraBadge;

  @override
  State<BuyerProfileAvatar> createState() => _BuyerProfileAvatarState();
}

class _BuyerProfileAvatarState extends State<BuyerProfileAvatar> {
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<AppStore>().uploadAvatar(
            file.path,
            filename: file.name,
            contentType: file.mimeType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await context.read<AppStore>().removeAvatar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture removed')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPicker() async {
    if (!widget.editable || _busy) return;
    final hasPhoto = (widget.avatar ?? '').trim().isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Profile picture',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add a photo so sellers can recognise you.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.ringOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
                ),
                title: const Text('Take photo', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.ringOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
                ),
                title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (hasPhoto)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_outline, color: AppColors.danger),
                  ),
                  title: const Text(
                    'Remove photo',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
                  ),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'camera') {
      await _pick(ImageSource.camera);
    } else if (action == 'gallery') {
      await _pick(ImageSource.gallery);
    } else if (action == 'remove') {
      await _remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.name.trim();
    final initial = trimmed.isEmpty ? 'U' : trimmed.substring(0, 1).toUpperCase();
    final url = ApiConfig.resolveMediaUrl(widget.avatar);
    final size = widget.radius * 2;

    final placeholder = Container(
      color: AppColors.accent,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: widget.radius * 0.85,
        ),
      ),
    );

    final avatar = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );

    final body = Stack(
      alignment: Alignment.center,
      children: [
        avatar,
        if (_busy)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              ),
            ),
          ),
        if (widget.editable && widget.showCameraBadge && !_busy)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: widget.radius * 0.72,
              height: widget.radius * 0.72,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.camera_alt, color: Colors.white, size: widget.radius * 0.38),
            ),
          ),
      ],
    );

    if (!widget.editable) return body;

    return GestureDetector(
      onTap: _openPicker,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

/// A store's shop photo, falling back to its initial while the photo is missing
/// or still loading.
class StoreAvatar extends StatelessWidget {
  const StoreAvatar({
    super.key,
    required this.name,
    required this.photo,
    this.radius = 22,
  });

  final String? name;
  final String? photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = (name ?? '').trim();
    final initial = trimmed.isEmpty ? 'S' : trimmed.substring(0, 1).toUpperCase();
    final url = ApiConfig.resolveMediaUrl(photo);
    final placeholder = Container(
      color: AppColors.ringOrange,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.8,
        ),
      ),
    );

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: url.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class AppLoader extends StatelessWidget {
  const AppLoader({
    super.key,
    this.label,
    this.color = AppColors.accent,
    this.size = 28,
  });

  final String? label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 14),
          Text(
            label!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color == Colors.white ? Colors.white70 : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class FullPageLoader extends StatelessWidget {
  const FullPageLoader({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: AppLoader(label: label));
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.height = 40,
    this.light = false,
    this.rounded = false,
  });

  final double height;
  final bool light;
  final bool rounded;

  static const assetPath = 'assets/branding/cityshop_logo.png';

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      assetPath,
      height: height,
      width: height,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stack) => Container(
        height: height,
        width: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: light ? Colors.white24 : AppColors.ringOrange,
          borderRadius: BorderRadius.circular(rounded ? height * 0.22 : 12),
        ),
        child: Text(
          'CS',
          style: TextStyle(
            fontSize: height * 0.32,
            fontWeight: FontWeight.w900,
            color: light ? Colors.white : AppColors.accent,
          ),
        ),
      ),
    );

    if (!rounded) return image;

    return ClipRRect(
      borderRadius: BorderRadius.circular(height * 0.22),
      child: image,
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
