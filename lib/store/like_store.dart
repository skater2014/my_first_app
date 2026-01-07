// lib/store/like_store.dart
import '../model/post.dart';

class LikeStore {
  static final List<Post> _likedPosts = [];

  static List<Post> get likedPosts => List.unmodifiable(_likedPosts);

  static bool isLiked(Post post) {
    return _likedPosts.any((p) => p.id == post.id);
  }

  static void toggle(Post post) {
    final index = _likedPosts.indexWhere((p) => p.id == post.id);
    if (index >= 0) {
      _likedPosts.removeAt(index);
    } else {
      _likedPosts.add(post);
    }
  }
}
