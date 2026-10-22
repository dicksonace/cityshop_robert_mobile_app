import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/api_client.dart';
import '../../theme/app_theme.dart';

/// Result of the in-app payment page.
class PaymentScreenResult {
  const PaymentScreenResult({this.paid = false, this.dashboard = false});

  final bool paid;
  final bool dashboard;
}

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
  bool _failed = false;
  bool _canRetry = false;
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
            if (_isFailedReturn(request.url)) {
              _showFailed(cancelled: true);
              return NavigationDecision.prevent;
            }
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

  bool _isFailedReturn(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (!_isReturnUrl(url) &&
        !url.contains('paystack/mobile-return') &&
        !url.contains('flutterwave/mobile-return')) {
      return false;
    }
    final status = (uri.queryParameters['status'] ?? '').toLowerCase();
    return status == 'cancelled' ||
        status == 'canceled' ||
        status == 'failed' ||
        status == 'failure' ||
        status == 'error';
  }

  void _showFailed({required bool cancelled, String? message}) {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _verifying = false;
      _loading = false;
      _canRetry = !cancelled;
      _error = message;
    });
  }

  void _returnToDashboard() {
    Navigator.of(context).pop(const PaymentScreenResult(dashboard: true));
  }

  Future<void> _maybeHandleReturn(String url) async {
    if (_verifying || _failed) return;
    if (_isFailedReturn(url)) {
      _showFailed(cancelled: true);
      return;
    }
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
      Navigator.of(context).pop(const PaymentScreenResult(paid: true));
    } on ApiException catch (e) {
      if (!mounted) return;
      _showFailed(cancelled: false, message: e.message);
    } catch (e) {
      if (!mounted) return;
      _showFailed(cancelled: false, message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(const PaymentScreenResult()),
        ),
      ),
      body: _failed
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  const Text(
                    'Payment was not successful',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  if (_error != null &&
                      _error!.trim().toLowerCase() != 'payment was not successful' &&
                      _error!.trim().toLowerCase() != 'payment was not successful.') ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _returnToDashboard,
                    child: const Text('Return to Dashboard'),
                  ),
                  if (_canRetry) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _failed = false;
                          _error = null;
                        });
                        _verify(widget.reference);
                      },
                      child: const Text('Retry confirm payment'),
                    ),
                  ],
                ],
              ),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading || _verifying)
                  const ColoredBox(
                    color: Color(0x66FFFFFF),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}
