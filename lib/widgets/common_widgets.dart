import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_config.dart';
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
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
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
