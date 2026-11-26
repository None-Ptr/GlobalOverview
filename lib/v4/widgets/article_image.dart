// Hallmark · component: article image · genre: editorial · theme: project (V4 tokens) · states: loading, loaded, failed
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:global_overview/providers/providers.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// One figure inside the article: a 16:9 quiet block while it resolves, the
/// real aspect once it lands, nothing at all when it cannot be fetched.
class V4ArticleImage extends ConsumerStatefulWidget {
  final String url;
  final String? alt;

  const V4ArticleImage({super.key, required this.url, this.alt});

  @override
  ConsumerState<V4ArticleImage> createState() => _V4ArticleImageState();
}

class _V4ArticleImageState extends ConsumerState<V4ArticleImage> {
  File? _file;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final file = await ref.read(imageCacheProvider).resolve(widget.url);
    if (!mounted) return;
    setState(() {
      _file = file;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // On the web the image goes straight into the page: <img> is fetched by
    // the browser itself, so the publisher's CORS policy does not apply.
    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(V4Radius.control),
        child: Image.network(
          widget.url,
          fit: BoxFit.fitWidth,
          alignment: Alignment.centerLeft,
          semanticLabel: widget.alt,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    final v4 = context.v4;
    final file = _file;
    if (!_done) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: v4.surfaceSubtle,
            borderRadius: BorderRadius.circular(V4Radius.control),
          ),
        ),
      );
    }
    if (file == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final target = (constraints.maxWidth * ratio).round();
        return ClipRRect(
          borderRadius: BorderRadius.circular(V4Radius.control),
          child: Image.file(
            file,
            fit: BoxFit.fitWidth,
            alignment: Alignment.centerLeft,
            cacheWidth: target.clamp(1, 2400),
            semanticLabel: widget.alt,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  ),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}