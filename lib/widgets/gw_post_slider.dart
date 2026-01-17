import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../model/gw_slider_item.dart';
import '../widgets/gw_youtube_player.dart';
import '../utils/gw_youtube.dart';

class GwPostSlider extends StatefulWidget {
  const GwPostSlider({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.autoPlayVideo = true,
    this.mute = true,
  });

  final List<GwSliderItem> items;
  final int initialIndex;
  final bool autoPlayVideo;
  final bool mute;

  @override
  State<GwPostSlider> createState() => _GwPostSliderState();
}

class _GwPostSliderState extends State<GwPostSlider> {
  late int _index;

  static const double _ratio = 16 / 9;
  static const double _thumbH = 74;
  static const double _thumbW = 118;

  bool get _canPlayYoutube {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    // ✅ macOS/Windows/Linux は false（153回避）
  }

  @override
  void initState() {
    super.initState();
    _index = _clampIndex(widget.initialIndex, widget.items.length);
  }

  @override
  void didUpdateWidget(covariant GwPostSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _index = _clampIndex(_index, widget.items.length);
  }

  int _clampIndex(int i, int len) {
    if (len <= 0) return 0;
    if (i < 0) return 0;
    if (i >= len) return len - 1;
    return i;
  }

  void _prev() {
    final len = widget.items.length;
    if (len == 0) return;
    setState(() => _index = (_index - 1) < 0 ? len - 1 : _index - 1);
  }

  void _next() {
    final len = widget.items.length;
    if (len == 0) return;
    setState(() => _index = (_index + 1) >= len ? 0 : _index + 1);
  }

  void _tapThumb(int i) {
    final len = widget.items.length;
    if (len == 0) return;
    setState(() => _index = _clampIndex(i, len));
  }

  String? _safeImageUrl(String? url) {
    if (url == null) return null;
    final t = url.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase().split('?').first;
    if (lower.endsWith('.avif')) return null;
    return t;
  }

  String? _thumbUrl(GwSliderItem it) {
    final t = _safeImageUrl(it.thumb);
    if (t != null) return t;

    final ytThumb = gwYoutubeThumbFromSrc(it.src);
    if (ytThumb != null) return ytThumb;

    return _safeImageUrl(it.src);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final it = items[_index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: _ratio,
              child: _MainMedia(
                item: it,
                canPlayYoutube: _canPlayYoutube,
                autoPlay: widget.autoPlayVideo,
                mute: widget.mute,
              ),
            ),
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(icon: Icons.chevron_left, onTap: _prev),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(icon: Icons.chevron_right, onTap: _next),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _thumbH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final t = items[i];
              final selected = i == _index;
              final thumb = _thumbUrl(t);

              return InkWell(
                onTap: () => _tapThumb(i),
                child: Opacity(
                  opacity: selected ? 1.0 : 0.6,
                  child: Container(
                    width: _thumbW,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                      color: Colors.black12,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumb == null
                        ? Container(color: Colors.black12)
                        : CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: Colors.black12),
                            errorWidget: (_, __, ___) =>
                                Container(color: Colors.black12),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MainMedia extends StatelessWidget {
  const _MainMedia({
    required this.item,
    required this.canPlayYoutube,
    required this.autoPlay,
    required this.mute,
  });

  final GwSliderItem item;
  final bool canPlayYoutube;
  final bool autoPlay;
  final bool mute;

  String? _safeImageUrl(String? url) {
    if (url == null) return null;
    final t = url.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase().split('?').first;
    if (lower.endsWith('.avif')) return null;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final id = gwExtractYoutubeId(item.src);

    // ✅ YouTube
    if (id != null && id.isNotEmpty) {
      // macOS/Windows/Linux はプレイヤーを作らない（153回避）→ サムネ
      if (!canPlayYoutube) {
        final thumb = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
        return CachedNetworkImage(
          imageUrl: thumb,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: Colors.black12),
          errorWidget: (_, __, ___) => Container(color: Colors.black12),
        );
      }

      return IgnorePointer(
        ignoring: true,
        child: GwYoutubePlayer(
          key: ValueKey('yt:$id'),
          videoId: id,
          autoPlay: autoPlay,
          mute: mute,
          useCard: false,
          useAspectRatio: false,
        ),
      );
    }

    // ✅ Image
    final img = _safeImageUrl(item.src);
    if (img == null) return Container(color: Colors.black12);

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final w = MediaQuery.of(context).size.width;
    final cacheW = (w * dpr).round();
    final cacheH = (w / (16 / 9) * dpr).round();

    return CachedNetworkImage(
      imageUrl: img,
      fit: BoxFit.cover,
      memCacheWidth: cacheW,
      memCacheHeight: cacheH,
      placeholder: (_, __) => Container(color: Colors.black12),
      errorWidget: (_, __, ___) => Container(color: Colors.black12),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
