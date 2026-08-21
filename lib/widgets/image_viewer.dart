import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'common_widgets.dart';

/// Opens [urls] full screen with pinch and double-tap zoom.
Future<void> showImageViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return Future.value();

  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageViewer(urls: urls, initialIndex: initialIndex),
    ),
  );
}

class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.urls, this.initialIndex = 0});

  final List<String> urls;
  final int initialIndex;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  static const _maxScale = 4.0;

  late final PageController _pageController;
  final _transform = TransformationController();
  late int _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
    _transform.addListener(_watchZoom);
  }

  @override
  void dispose() {
    _transform.removeListener(_watchZoom);
    _transform.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Swiping to the next image has to yield to panning a zoomed-in one.
  void _watchZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _resetZoom() => _transform.value = Matrix4.identity();

  void _zoomToCentre() {
    final size = MediaQuery.sizeOf(context);
    _toggleZoom(TapDownDetails(localPosition: Offset(size.width / 2, size.height / 2)));
  }

  void _toggleZoom(TapDownDetails details) {
    if (_zoomed) {
      _resetZoom();
      return;
    }

    // Zoom towards the point that was tapped.
    final target = details.localPosition;
    const scale = 2.5;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-target.dx * (scale - 1), -target.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.urls.length) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: total,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            onPageChanged: (i) {
              _resetZoom();
              setState(() => _index = i);
            },
            itemBuilder: (context, i) {
              final image = CachedNetworkImage(
                imageUrl: widget.urls[i],
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(child: AppLoader(color: Colors.white)),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 56, color: Colors.white54),
                ),
              );

              // Only the visible page owns the shared zoom controller.
              if (i != _index) {
                return SizedBox.expand(child: Center(child: image));
              }

              return GestureDetector(
                onDoubleTapDown: _toggleZoom,
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: _transform,
                  maxScale: _maxScale,
                  minScale: 1,
                  child: SizedBox.expand(
                    child: Center(child: image),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  if (total > 1)
                    Text(
                      '${_index + 1} / $total',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: _zoomed ? 'Reset zoom' : 'Zoom in',
                    onPressed: _zoomed ? _resetZoom : _zoomToCentre,
                    icon: Icon(
                      _zoomed ? Icons.zoom_out_map : Icons.zoom_in,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (total > 1 && !_zoomed) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ViewerNavButton(
                  icon: Icons.chevron_left,
                  onTap: () => _goTo(_index - 1),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ViewerNavButton(
                  icon: Icons.chevron_right,
                  onTap: () => _goTo(_index + 1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ViewerNavButton extends StatelessWidget {
  const _ViewerNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
