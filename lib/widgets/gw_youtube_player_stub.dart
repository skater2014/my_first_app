import 'package:flutter/material.dart';

Widget buildGwYoutubePlayer({
  required BuildContext context,
  required String videoId,
  required bool autoPlay,
  required bool mute,
  required bool useAspectRatio,
  required bool useCard,
}) {
  Widget child = Container(color: Colors.black12);

  if (useAspectRatio) {
    child = AspectRatio(aspectRatio: 16 / 9, child: child);
  }
  if (!useCard) return child;

  return Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
