// lib/widgets/gw_post_slider.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../model/gw_slider_item.dart';

/// ============================================================
/// GwPostSlider
/// - 記事の先頭に出す「複数メディア（画像/YouTube）スライダー」
/// - 上：メイン表示（画像 or YouTube）
/// - 下：サムネ横並び（タップでメイン切替）
/// - 左右矢印で前後移動
/// ============================================================
class GwPostSlider extends StatefulWidget {
  final List<GwSliderItem> items;

  /// 任意：初期表示index
  final int initialIndex;

  const GwPostSlider({super.key, required this.items, this.initialIndex = 0});

  @override
  State<GwPostSlider> createState() => _GwPostSliderState();
}

class _GwPostSliderState extends State<GwPostSlider> {
  late int _index;

  YoutubePlayerController? _yt;

  @override
  void initState() {
    super.initState();

    _index = widget.items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.items.length - 1);

    // 初期がyoutubeならコントローラ準備
    _ensureYoutubeControllerIfNeeded(
      widget.items.isNotEmpty ? widget.items[_index] : null,
    );
  }

  @override
  void didUpdateWidget(covariant GwPostSlider oldWidget) {
    super.didUpdateWidget(oldWidget);

    // itemsが差し替わった時の安全策
    if (widget.items.isEmpty) {
      _index = 0;
      _yt?.dispose();
      _yt = null;
      return;
    }
    if (_index >= widget.items.length) {
      setState(() => _index = widget.items.length - 1);
      _ensureYoutubeControllerIfNeeded(widget.items[_index]);
    }
  }

  @override
  void dispose() {
    _yt?.dispose();
    super.dispose();
  }

  /// ------------------------------------------
  /// YouTube補助
  /// ------------------------------------------
  String? _videoIdFrom(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(t) ?? t; // urlでもidでもOK
  }

  String? _youtubeThumbFrom(String raw) {
    final id = _videoIdFrom(raw);
    if (id == null) return null;
    return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }

  void _ensureYoutubeControllerIfNeeded(GwSliderItem? item) {
    if (item == null) return;
    if (item.type != 'youtube') return;

    final id = _videoIdFrom(item.src);
    if (id == null) return;

    if (_yt == null) {
      _yt = YoutubePlayerController(
        initialVideoId: id,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: true,
        ),
      );
    } else {
      _yt!.load(id);
    }
  }

  /// ------------------------------------------
  /// 操作：前後移動
  /// ------------------------------------------
  void _prev() {
    if (widget.items.isEmpty) return;
    final next = (_index - 1) < 0 ? widget.items.length - 1 : _index - 1;
    setState(() => _index = next);
    _ensureYoutubeControllerIfNeeded(widget.items[_index]);
  }

  void _next() {
    if (widget.items.isEmpty) return;
    final next = (_index + 1) >= widget.items.length ? 0 : _index + 1;
    setState(() => _index = next);
    _ensureYoutubeControllerIfNeeded(widget.items[_index]);
  }

  void _tapThumb(int i) {
    if (i < 0 || i >= widget.items.length) return;
    setState(() => _index = i);
    _ensureYoutubeControllerIfNeeded(widget.items[_index]);
  }

  /// ------------------------------------------
  /// UI
  /// ------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final item = widget.items[_index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ===== メイン（16:9） =====
        Stack(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildMain(item)),

            // 左矢印
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(icon: Icons.chevron_left, onTap: _prev),
              ),
            ),

            // 右矢印
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

        // ===== サムネ（横スクロール） =====
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final it = widget.items[i];
              final selected = i == _index;

              // thumbがあればそれ、無ければ
              // - youtube → youtubeサムネ
              // - image   → srcをサムネとして使う
              final thumbUrl = (it.thumb != null && it.thumb!.trim().isNotEmpty)
                  ? it.thumb!.trim()
                  : (it.type == 'youtube' ? _youtubeThumbFrom(it.src) : it.src);

              return InkWell(
                onTap: () => _tapThumb(i),
                child: Opacity(
                  opacity: selected ? 1.0 : 0.6,
                  child: Container(
                    width: 118,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? Colors.blueAccent
                            : Colors.transparent,
                        width: 2,
                      ),
                      color: Colors.black12,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumbUrl == null
                        ? Center(
                            child: Icon(
                              it.type == 'youtube'
                                  ? Icons.play_circle
                                  : Icons.image,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: thumbUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (_, __, ___) =>
                                const Center(child: Icon(Icons.broken_image)),
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

  /// メイン表示（画像 or YouTube）
  Widget _buildMain(GwSliderItem item) {
    if (item.type == 'youtube') {
      // controllerが無い＝IDが取れない等
      if (_yt == null) {
        return const Center(child: Icon(Icons.play_circle, size: 56));
      }
      return YoutubePlayer(controller: _yt!, showVideoProgressIndicator: true);
    }

    // image
    return CachedNetworkImage(
      imageUrl: item.src,
      fit: BoxFit.cover,
      placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
      errorWidget: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image)),
    );
  }
}

/// 矢印ボタン（半透明の丸ボタン）
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

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
