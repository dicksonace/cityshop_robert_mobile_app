import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Privacy Policy and Terms links shown on login and create-account screens.
class AuthLegalLinks extends StatelessWidget {
  const AuthLegalLinks({super.key});

  static const _privacy = 'https://cityunlock.net/privacy';
  static const _terms = 'https://cityunlock.net/terms';

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, height: 1.4, color: Colors.grey.shade600);
    final link = muted.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.accent,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('By continuing you agree to our ', style: muted),
          GestureDetector(
            onTap: () => _open(_terms),
            child: Text('Terms of Service', style: link),
          ),
          Text(' and ', style: muted),
          GestureDetector(
            onTap: () => _open(_privacy),
            child: Text('Privacy Policy', style: link),
          ),
          Text('.', style: muted),
        ],
      ),
    );
  }
}
