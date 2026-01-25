// lib/widgets/gw_side_drawer.dart
import 'package:flutter/material.dart';
import '../service/wp_api_service.dart';

/// ============================================================
/// GwSideDrawer
/// - Drawer内に「Contactフォーム」を直接描画して、自作RESTへ送る
/// - 別ページに飛ばさない
///
/// ✅送信先
///   https://gamewidth.net/wp-json/gwc/v1/contact
///
/// ✅注意
/// - Drawer内は狭いので ExpansionTile で開閉
/// - キーボードで隠れないように viewInsets を bottom padding に反映
/// ============================================================
class GwSideDrawer extends StatelessWidget {
  const GwSideDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              child: Text('GameWidth', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),

            // ---- 既存メニュー ----
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('Categories'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Likes'),
              onTap: () => Navigator.pop(context),
            ),

            const Divider(),

            // ✅ Drawer内に直接 Contact フォームを描画
            const _ContactFormInDrawer(),

            const Divider(),

            // これはURLで開く方式にしたいなら後で追加（今はなくてもOK）
            // Privacy Policy は既にサイト側にあるので「Webへ飛ばす」で十分
          ],
        ),
      ),
    );
  }
}

/// ============================================================
/// _ContactFormInDrawer
/// - ここがフォーム本体
/// - 自作RESTへJSONで送る
/// ============================================================
class _ContactFormInDrawer extends StatefulWidget {
  const _ContactFormInDrawer();

  @override
  State<_ContactFormInDrawer> createState() => _ContactFormInDrawerState();
}

class _ContactFormInDrawerState extends State<_ContactFormInDrawer> {
  final _api = WpApiService();
  final _formKey = GlobalKey<FormState>();

  // 入力
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  // -----------------------------
  // ✅ 送信処理（自作RESTへ）
  // -----------------------------
  Future<void> _submit() async {
    if (_sending) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _api.sendContact(
        name: _name.text,
        email: _email.text,
        subject: _subject.text,
        message: _message.text,
      );

      if (!mounted) return;

      // ✅ 成功：クリア
      _name.clear();
      _email.clear();
      _subject.clear();
      _message.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('送信しました。返信をお待ちください。')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '送信エラー: $e');
    } finally {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  // -----------------------------
  // ✅ バリデーション
  // -----------------------------
  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return '必須です';
    return null;
  }

  String? _emailValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '必須です';
    if (!t.contains('@')) return 'メール形式が正しくない';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // ✅ キーボードで隠れないように bottom padding を増やす
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return ExpansionTile(
      leading: const Icon(Icons.mail_outline),
      title: const Text('Contact'),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('お問い合わせ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
                const SizedBox(height: 10),
              ],

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 10),

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your email',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: _emailValidator,
                    ),
                    const SizedBox(height: 10),

                    TextFormField(
                      controller: _subject,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Subject (optional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    TextFormField(
                      controller: _message,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _submit,
                        child: _sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Submit'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
