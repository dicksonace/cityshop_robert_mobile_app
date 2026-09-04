import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/api_client.dart';
import '../../theme/app_theme.dart';

/// In-app Paystack checkout — stays inside CityShop (no external browser).
class PaystackPaymentScreen extends StatefulWidget {
  const PaystackPaymentScreen({
    super.key,
    required this.authorizationUrl,
    required this.reference,
    required this.onVerify,
  });

  final String authorizationUrl;
  final String reference;
  final Future<void> Function(String reference) onVerify;

  @override
  State<PaystackPaymentScreen> createState() => _PaystackPaymentScreenState();
}

class _PaystackPaymentScreenState extends State<PaystackPaymentScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            _maybeHandleReturn(request.url);
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _maybeHandleReturn(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  bool _isReturnUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    if (path.contains('paystack/mobile-return')) return true;
    if (path.contains('flutterwave/mobile-return')) return true;
    if (path.contains('checkout/callback')) return true;
    if (path.contains('checkout/flutterwave/callback')) return true;
    if (path.contains('wallet/callback')) return true;
    if (path.contains('wallet/flutterwave/callback')) return true;
    if ((uri.queryParameters.containsKey('reference') ||
            uri.queryParameters.containsKey('trxref') ||
            uri.queryParameters.containsKey('tx_ref')) &&
        (path.contains('callback') ||
            path.contains('mobile-return') ||
            path.contains('close') ||
            url.contains('cityshop-paystack-done') ||
            url.contains('cityshop-flutterwave-done'))) {
      return true;
    }
    return false;
  }

  String? _referenceFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final ref = uri.queryParameters['reference'] ??
        uri.queryParameters['trxref'] ??
        uri.queryParameters['tx_ref'];
    if (ref != null && ref.isNotEmpty) return ref;
    return widget.reference;
  }

  Future<void> _maybeHandleReturn(String url) async {
    if (_verifying) return;
    if (!_isReturnUrl(url) &&
        !url.contains('paystack/mobile-return') &&
        !url.contains('flutterwave/mobile-return')) {
      return;
    }

    final reference = _referenceFromUrl(url) ?? widget.reference;
    await _verify(reference);
  }

  Future<void> _verify(String reference) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      await widget.onVerify(reference);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading || _verifying)
            const ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => _verify(widget.reference),
                        child: const Text('Retry confirm payment'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
