// lib/screens/genshin_character_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:my_first_app/model/character.dart';
import 'package:my_first_app/model/post.dart';
import 'package:my_first_app/service/wp_api_service.dart';

import 'package:my_first_app/features/genshin_build/character_html_parser.dart';
import 'package:my_first_app/features/genshin_build/character_build_widgets.dart';

class GenshinCharacterDetailScreen extends StatelessWidget {
  final GenshinCharacter character;
  final String base;

  const GenshinCharacterDetailScreen({
    super.key,
    required this.character,
    this.base = 'wp/v2/my-genshin-builds',
  });

  Future<Post?> _fetchPost() async {
    final api = WpApiService();

    final byId = await api.fetchSingleById(base, character.id);
    if (byId != null) return byId;

    final slug = character.resolvedSlug;
    if (slug.isEmpty) return null;

    return api.fetchSingleBySlug(base, slug);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Post?>(
      future: _fetchPost(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final post = snap.data;
        if (post == null) {
          return Scaffold(
            appBar: AppBar(title: Text(character.name)),
            body: Center(
              child: Text(
                'Detail not found (base=$base, id=${character.id}, slug=${character.resolvedSlug})',
              ),
            ),
          );
        }

        var data = parseCharacterHtml(post.contentHtml);
        debugPrint('HTML len=${post.contentHtml.length}');
        debugPrint('has character-skills=${post.contentHtml.contains("character-skills")}');
        debugPrint('groups=${data.skillGroups.length}');
        if (data.skillGroups.isNotEmpty) {
          debugPrint(
            'first group id=${data.skillGroups.first.id} title=${data.skillGroups.first.title} items=${data.skillGroups.first.items.length}',
          );
        }

        // パース失敗時の保険：あなたの character.dart を参照
        if (data.name.trim().isEmpty) {
          data = data.copyWith(name: character.name);
        }
        if (data.portraitUrl.trim().isEmpty) {
          data = data.copyWith(portraitUrl: character.portraitUrl);
        }

        return Scaffold(
          appBar: AppBar(title: Text(data.name)),
          body: CharacterDetailLayout(data: data),
        );
      },
    );
  }
}
