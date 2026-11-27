import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../PROVIDERS/fit_provider.dart';
import '../PROVIDERS/ootd_provider.dart';
import '../SERVICES/image_tools.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/auth_gate.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/app_network_image.dart';
import '../WIDGETS/studio_widgets.dart';
import '../WIDGETS/ui_kit.dart';
import 'camera_capture_page.dart';

/// Membuka form posting OOTD (wajib member). [photo] & [productIds] opsional.
Future<void> startOotdPost(
  BuildContext context, {
  Uint8List? photo,
  List<String> productIds = const [],
}) async {
  final ok = await requireMember(
    context,
    message: 'Membagikan OOTD khusus member UNIQLO. Masuk atau gabung member '
        'untuk memposting.',
  );
  if (!ok || !context.mounted) return;
  await pushPage(context, OotdPostPage(initialPhoto: photo, initialProductIds: productIds));
}

/// Umpan komunitas OOTD, bisa disaring menurut tinggi, warna kulit, dan produk.
class OotdPage extends StatefulWidget {
  const OotdPage({super.key});

  @override
  State<OotdPage> createState() => _OotdPageState();
}

class _OotdPageState extends State<OotdPage> {
  int? _heightBand; // 0: <160, 1: 160-170, 2: >170
  SkinTone? _skin;

  bool _matches(OotdPost p) {
    if (_heightBand != null) {
      final h = p.heightCm;
      if (h == null) return false;
      final band = h < 160 ? 0 : (h <= 170 ? 1 : 2);
      if (band != _heightBand) return false;
    }
    if (_skin != null && p.skinTone != _skin) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<AppState>().allProducts;
    final feed = context.watch<OotdProvider>().feed(catalog);
    final posts = feed.where(_matches).toList();
    const heightLabels = ['< 160 cm', '160–170 cm', '> 170 cm'];

    return Scaffold(
      appBar: AppBar(title: const Text('KOMUNITAS OOTD')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        onPressed: () => startOotdPost(context),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Posting OOTD'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(heightLabels[i]),
                      selected: _heightBand == i,
                      onSelected: (v) => setState(() => _heightBand = v ? i : null),
                    ),
                  ),
                for (final s in SkinTone.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('Kulit ${s.label.toLowerCase()}'),
                      selected: _skin == s,
                      onSelected: (v) => setState(() => _skin = v ? s : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: posts.isEmpty
                ? const EmptyState(
                    icon: Icons.groups_2_outlined,
                    title: 'Belum ada OOTD yang cocok',
                    message: 'Coba ubah filter, atau jadi yang pertama memposting.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: posts.length,
                    itemBuilder: (context, i) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _PostCard(post: posts[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final OotdPost post;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final provider = context.read<OotdProvider>();
    final products = <Product>[
      for (final id in post.productIds)
        if (app.productById(id) != null) app.productById(id)!,
    ];
    final info = <String>[
      if (post.heightCm != null) '${post.heightCm!.round()} cm',
      if (post.weightKg != null) '${post.weightKg!.round()} kg',
      if (post.sizeWorn.isNotEmpty) 'Ukuran ${post.sizeWorn}',
      if (post.skinTone != null) 'Kulit ${post.skinTone!.label.toLowerCase()}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: cardDecoration(radius: 16, border: true, shadow: false),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.redSoft,
              child: Text(
                post.author.isEmpty ? '?' : post.author[0].toUpperCase(),
                style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800),
              ),
            ),
            title: Text(post.author, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: info.isEmpty ? null : Text(info.join(' • ')),
            trailing: post.isSample
                ? const PillTag(label: 'CONTOH', color: Colors.black54)
                : PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'delete') provider.deletePost(post.id);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Hapus postingan')),
                    ],
                  ),
          ),
          if (post.photo != null)
            AspectRatio(
              aspectRatio: 4 / 5,
              child: StoredImage(post.photo!, fit: BoxFit.cover),
            )
          else if (products.isNotEmpty)
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  for (final p in products.take(3))
                    Expanded(
                      child: AppNetworkImage(p.image, fit: BoxFit.cover, height: 200),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(post.caption, style: const TextStyle(height: 1.4)),
          ),
          if (products.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(
                'Produk yang dipakai',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.muted),
              ),
            ),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => MiniProductTile(product: products[i], width: 120),
              ),
            ),
          ],
          Row(
            children: [
              TextButton.icon(
                onPressed: () => provider.toggleLike(post),
                icon: Icon(
                  post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: AppColors.red,
                  size: 20,
                ),
                label: Text('${post.likes}', style: const TextStyle(color: AppColors.ink)),
              ),
              TextButton.icon(
                onPressed: () => _showComments(context, post.id),
                icon: const Icon(Icons.chat_bubble_outline, size: 20, color: AppColors.ink),
                label: Text('${post.comments.length}', style: const TextStyle(color: AppColors.ink)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showComments(BuildContext context, String postId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CommentsSheet(postId: postId),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId});

  final String postId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<AppState>().allProducts;
    final post = context.watch<OotdProvider>().byId(widget.postId, catalog);
    if (post == null) return const SizedBox(height: 120);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Komentar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: post.comments.isEmpty
                  ? const Center(child: Text('Belum ada komentar'))
                  : ListView(
                      children: [
                        for (final c in post.comments)
                          ListTile(
                            dense: true,
                            title: Text(c.author, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(c.text),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Tulis komentar',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final name = context.read<AuthProvider>().currentMember?.name ?? 'Tamu';
                      context.read<OotdProvider>().addComment(post, name, _text.text);
                      _text.clear();
                    },
                    icon: const Icon(Icons.send, color: AppColors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Posting
// -----------------------------------------------------------------------------

class OotdPostPage extends StatefulWidget {
  const OotdPostPage({super.key, this.initialPhoto, this.initialProductIds = const []});

  final Uint8List? initialPhoto;
  final List<String> initialProductIds;

  @override
  State<OotdPostPage> createState() => _OotdPostPageState();
}

class _OotdPostPageState extends State<OotdPostPage> {
  final TextEditingController _caption = TextEditingController();
  final TextEditingController _size = TextEditingController();
  Uint8List? _photo;
  late List<String> _productIds = [...widget.initialProductIds];
  bool _shareBody = true;
  SkinTone? _skin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPhoto;
    if (initial != null) _prepare(initial);
  }

  @override
  void dispose() {
    _caption.dispose();
    _size.dispose();
    super.dispose();
  }

  Future<void> _prepare(Uint8List bytes) async {
    setState(() => _busy = true);
    try {
      final png = await downscalePhoto(bytes);
      if (mounted) setState(() => _photo = png);
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Foto tidak bisa diproses.',
            color: AppColors.red, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takePhoto() async {
    final bytes = await pushPage<Uint8List>(
      context,
      const CameraCapturePage(
        title: 'Foto OOTD',
        hint: 'Berdiri agar outfit terlihat dari kepala sampai kaki.',
        showFaceGuide: false,
        preferFront: false,
      ),
    );
    if (bytes != null) await _prepare(bytes);
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
      final bytes = await picked?.readAsBytes();
      if (bytes != null) await _prepare(bytes);
    } catch (_) {}
  }

  Future<void> _addProduct() async {
    final catalog = context.read<AppState>().allProducts;
    final p = await pickCatalogProduct(context, catalog, title: 'Tag produk yang dipakai');
    if (p != null && !_productIds.contains(p.id)) {
      setState(() => _productIds = [..._productIds, p.id]);
    }
  }

  Future<void> _post() async {
    if (_busy) return;
    if (_photo == null && _productIds.isEmpty) {
      showAppToast(context, 'Tambahkan foto atau tag minimal satu produk.',
          color: AppColors.red, icon: Icons.info_outline);
      return;
    }
    setState(() => _busy = true);
    final fit = context.read<FitProvider>();
    final author = context.read<AuthProvider>().currentMember?.name ?? 'Tamu';
    try {
      await context.read<OotdProvider>().addPost(
            author: author,
            caption: _caption.text,
            photoPng: _photo,
            productIds: _productIds,
            heightCm: _shareBody && fit.hasSavedProfile ? fit.profile.heightCm : null,
            weightKg: _shareBody && fit.hasSavedProfile ? fit.profile.weightKg : null,
            sizeWorn: _size.text.trim(),
            skinTone: _skin,
          );
      if (!mounted) return;
      showAppToast(context, 'OOTD diposting');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, 'Gagal memposting.', color: AppColors.red, icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final fit = context.watch<FitProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('POSTING OOTD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 320,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _busy && _photo == null
                        ? const Center(child: CircularProgressIndicator())
                        : _photo == null
                            ? const Center(child: Icon(Icons.image_outlined, size: 48, color: Colors.black26))
                            : Image.memory(_photo!, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Kamera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeri'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _caption,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Cerita outfit-mu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Produk yang dipakai', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final id in _productIds)
                        InputChip(
                          label: Text(
                            app.productById(id)?.name ?? id,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => setState(
                            () => _productIds = _productIds.where((e) => e != id).toList(),
                          ),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Tag produk'),
                        onPressed: _addProduct,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _size,
                    decoration: const InputDecoration(
                      labelText: 'Ukuran yang kamu pakai (mis. M)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Warna kulit (opsional)', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in SkinTone.values)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: _skin == s,
                          onSelected: (v) => setState(() => _skin = v ? s : null),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _shareBody && fit.hasSavedProfile,
                    onChanged: fit.hasSavedProfile ? (v) => setState(() => _shareBody = v) : null,
                    title: const Text('Tampilkan tinggi & berat badan'),
                    subtitle: Text(
                      fit.hasSavedProfile
                          ? 'Membantu orang lain membayangkan ukuran. '
                              '${fit.profile.heightCm.round()} cm, ${fit.profile.weightKg.round()} kg'
                          : 'Isi dulu di Kalkulator Ukuran untuk membagikannya.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: _busy ? null : _post,
                    child: Text(_busy ? 'Memproses...' : 'POSTING'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
