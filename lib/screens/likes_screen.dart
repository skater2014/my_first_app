// lib/screens/likes_screen.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../store/like_store.dart';
import '../model/post.dart';

class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key});

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen> {
  @override
  Widget build(BuildContext context) {
    final List<Post> liked = LikeStore.likedPosts;

    return Scaffold(
      appBar: AppBar(title: const Text('Liked Posts')),
      body: liked.isEmpty
          ? const Center(child: Text('まだ いいね した記事がありません'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: liked.length,
              itemBuilder: (context, index) {
                final post = liked[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: (post.imageUrl != null)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: post.imageUrl!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.article),
                    title: Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${post.date.toLocal()}'.split(' ').first,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    onTap: () {
                      // TODO: 投稿詳細へ遷移
                    },
                  ),
                );
              },
            ),
    );
  }
}
