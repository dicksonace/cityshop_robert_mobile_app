import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../store/app_store.dart';
import '../../widgets/common_widgets.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _messages = [
    (
      title: "Ghana's Trusted Marketplace",
      body: 'Shop verified sellers with buyer protection on every order.',
    ),
    (
      title: 'Deals delivered nationwide',
      body: 'Phones, fashion, vehicles and more — from Accra to your doorstep.',
    ),
    (
      title: 'Compare & save with confidence',
      body: 'Browse live prices, wishlists, and secure checkout in one app.',
    ),
  ];

  late final AnimationController _intro;
  late final AnimationController _float;
  late final AnimationController _ring;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textFade;

  int _messageIndex = 0;
  Timer? _messageTimer;
  bool _ready = false;
  bool _entered = false;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _logoScale = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
    _logoFade = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.4, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(parent: _intro, curve: const Interval(0.35, 0.9, curve: Curves.easeOutCubic)),
    );
    _textFade = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 1, curve: Curves.easeOut));

    _intro.forward();
    _messageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  /// Always release the router lock, then open the shop.
  /// Without [AppStore.finishBoot], Skip intro / timeout navigated to /shop and
  /// the redirect bounced straight back to splash — looked like a freeze.
  void _enterApp() {
    if (_entered || !mounted) return;
    _entered = true;
    final store = context.read<AppStore>();
    store.finishBoot();
    if (mounted) setState(() => _ready = true);
    context.go('/shop');
  }

  Future<void> _bootstrap() async {
    final store = context.read<AppStore>();
    // Kick init but never wait on it forever — network/Keystore can hang.
    unawaited(store.init());

    final started = DateTime.now();
    // Show branding briefly, then enter as soon as boot finishes (or 6s max).
    while (mounted && !_entered) {
      if (!store.booting) break;
      if (DateTime.now().difference(started) >= const Duration(seconds: 6)) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // Keep the intro visible at least ~2s so it doesn't flash.
    final shown = DateTime.now().difference(started);
    if (shown < const Duration(milliseconds: 2000)) {
      await Future<void>.delayed(const Duration(milliseconds: 2000) - shown);
    }
    if (!mounted || _entered) return;
    _enterApp();
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _intro.dispose();
    _float.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _messages[_messageIndex];

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFEA580C),
              Color(0xFFC2410C),
              Color(0xFF9A3412),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -30,
              child: _GlowOrb(size: 160, opacity: 0.12, controller: _float),
            ),
            Positioned(
              bottom: 80,
              left: -50,
              child: _GlowOrb(size: 180, opacity: 0.1, controller: _float, reverse: true),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: AnimatedBuilder(
                          animation: _float,
                          builder: (context, child) {
                            final dy = Tween(begin: -6.0, end: 6.0).evaluate(_float);
                            return Transform.translate(offset: Offset(0, dy), child: child);
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _ring,
                                builder: (context, _) {
                                  return CustomPaint(
                                    size: const Size(140, 140),
                                    painter: _RingPainter(progress: _ring.value),
                                  );
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 28,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: const BrandMark(height: 88, rounded: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _textFade,
                      child: SlideTransition(
                        position: _textSlide,
                        child: Column(
                          children: [
                            const Text(
                              'CityShop',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 18),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 450),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, anim) {
                                return FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.15),
                                      end: Offset.zero,
                                    ).animate(anim),
                                    child: child,
                                  ),
                                );
                              },
                              child: Column(
                                key: ValueKey(_messageIndex),
                                children: [
                                  Text(
                                    message.title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    message.body,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.88),
                                      fontSize: 14,
                                      height: 1.45,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(_messages.length, (i) {
                                final active = i == _messageIndex;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: active ? 18 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: active ? Colors.white : Colors.white38,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    AnimatedOpacity(
                      opacity: _ready ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation(
                                Colors.white.withValues(alpha: 0.95),
                              ),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Preparing your marketplace…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _enterApp,
                      child: Text(
                        'Skip intro',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.opacity,
    required this.controller,
    this.reverse = false,
  });

  final double size;
  final double opacity;
  final AnimationController controller;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = reverse ? 1 - controller.value : controller.value;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.9 + (t * 0.15),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final arc = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708 + (progress * 6.2832),
      1.6,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.progress != progress;
}
