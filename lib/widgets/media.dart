import 'dart:ui' show ImageFilter;
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// The 11-letter id inside a YouTube link, or null.
String? youtubeId(String? url) {
  if (url == null || url.isEmpty) return null;
  final m = RegExp(r'(?:youtu\.be/|v=|embed/|shorts/)([A-Za-z0-9_-]{11})').firstMatch(url);
  return m?.group(1);
}

String youtubeThumb(String id) => 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

/// Shows a picture from the web or from a "data:" link (demo mode).
/// Data saver: when on, pictures from the web wait for a tap.
final dataSaverProvider = StateNotifierProvider<DataSaverCtrl, bool>((ref) => DataSaverCtrl());

class DataSaverCtrl extends StateNotifier<bool> {
  DataSaverCtrl() : super(false) {
    SharedPreferences.getInstance().then((p) {
      if (mounted) state = p.getBool(_key) ?? false;
    }).catchError((_) {});
  }
  static const _key = 'data_saver';
  Future<void> set(bool on) async {
    state = on;
    try {
      (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
  }
}

class NetPicture extends ConsumerStatefulWidget {
  const NetPicture(this.url, {super.key, this.fit = BoxFit.cover, this.alwaysLoad = false, this.hideWhenSaving = false});
  final String url;
  final BoxFit fit;

  /// Full-screen viewer: the person already asked to see it.
  final bool alwaysLoad;

  /// A decoration (the blurred backdrop): with data saver on, draw nothing.
  final bool hideWhenSaving;

  @override
  ConsumerState<NetPicture> createState() => _NetPictureState();
}

class _NetPictureState extends ConsumerState<NetPicture> {
  bool _tapped = false;

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final fit = widget.fit;
    final s = Theme.of(context).colorScheme;
    final fallback = Container(
      color: s.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: s.outline),
    );
    if (url.startsWith('data:')) {
      try {
        return Image.memory(base64Decode(url.substring(url.indexOf(',') + 1)), fit: fit, gaplessPlayback: true);
      } catch (_) {
        return fallback;
      }
    }
    final saver = ref.watch(dataSaverProvider);
    if (saver && widget.hideWhenSaving) return const SizedBox.shrink();
    if (saver && !_tapped && !widget.alwaysLoad) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tapped = true),
        child: Container(
          color: s.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.download_rounded, color: s.outline),
            const SizedBox(height: 4),
            Text('Data saver · tap to load picture', style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );
    }
    final loading = Container(color: s.surfaceContainerHighest);
    if (kIsWeb) {
      // The browser keeps its own copy of pictures.
      return Image.network(
        url,
        fit: fit,
        // If the picture's server blocks the faster web renderer, still show it.
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (c, child, p) => p == null ? child : loading,
      );
    }
    // Phones and computers: keep a copy on disk so a picture downloads once.
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) => loading,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// 16:9 banner: the cover picture, or a YouTube preview with a play button.
class MediaBanner extends StatelessWidget {
  const MediaBanner({super.key, this.coverUrl, this.videoUrl, this.radius = 0, this.full = false});
  final String? coverUrl;
  final String? videoUrl;
  final double radius;
  /// Article view: show the whole picture at its own shape (no cropping),
  /// and tap opens it full screen with zoom.
  final bool full;

  static bool has({String? coverUrl, String? videoUrl}) =>
      (coverUrl ?? '').isNotEmpty || youtubeId(videoUrl) != null;

  @override
  Widget build(BuildContext context) {
    final id = youtubeId(videoUrl);
    final pic = (coverUrl ?? '').isNotEmpty ? coverUrl! : (id != null ? youtubeThumb(id) : null);
    if (pic == null) return const SizedBox.shrink();
    if (full && id == null) {
      return GestureDetector(
        onTap: () => openPictureViewer(context, pic),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Stack(alignment: Alignment.bottomRight, children: [
              NetPicture(pic, fit: BoxFit.contain),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.open_in_full_rounded, size: 16, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          // Whole picture on a soft blurred copy of itself, so posters with
          // text are never cut off.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Opacity(opacity: 0.55, child: NetPicture(pic, hideWhenSaving: true)),
          ),
          NetPicture(pic, fit: BoxFit.contain),
          if (id != null)
            Material(
              color: Colors.black.withValues(alpha: 0.18),
              child: InkWell(
                onTap: () => launchUrl(Uri.parse(videoUrl!), mode: LaunchMode.externalApplication),
                child: Center(
                  child: Container(
                    width: 62,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFFF0000), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A picture chooser box used on the "new post / new event" forms.
class CoverPicker extends StatelessWidget {
  const CoverPicker({super.key, required this.url, required this.busy, required this.onPick, required this.onClear});
  final String? url;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          color: s.surfaceContainerHighest.withValues(alpha: 0.5),
          child: InkWell(
            onTap: busy ? null : onPick,
            child: Stack(fit: StackFit.expand, children: [
              if ((url ?? '').isNotEmpty) NetPicture(url!),
              if ((url ?? '').isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  // Shrinks to fit when the phone's text size is large.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 36, color: s.primary),
                      const SizedBox(height: 6),
                      const Text('Add a cover picture (optional)'),
                      Text('We shrink it to under 1 MB for you', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              if (busy) const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
              if ((url ?? '').isNotEmpty && !busy)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(onPressed: onClear, icon: const Icon(Icons.close_rounded)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}


/// Full-screen picture: pinch or double-tap to zoom, swipe down or tap X to close.
Future<void> openPictureViewer(BuildContext context, String url) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => _PictureViewer(url: url),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _PictureViewer extends StatefulWidget {
  const _PictureViewer({required this.url});
  final String url;
  @override
  State<_PictureViewer> createState() => _PictureViewerState();
}

class _PictureViewerState extends State<_PictureViewer> {
  final _ctrl = TransformationController();
  double _drag = 0;

  void _toggleZoom(TapDownDetails d) {
    final zoomed = _ctrl.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed) {
      _ctrl.value = Matrix4.identity();
    } else {
      final p = d.localPosition;
      _ctrl.value = Matrix4.identity()
        ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zoomed = _ctrl.value.getMaxScaleOnAxis() > 1.01;
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: (1 - _drag.abs() / 400).clamp(0.3, 1.0)),
      body: Stack(children: [
        GestureDetector(
          onDoubleTapDown: _toggleZoom,
          onDoubleTap: () => setState(() {}),
          onVerticalDragUpdate: zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
          onVerticalDragEnd: zoomed
              ? null
              : (_) {
                  if (_drag.abs() > 120) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _drag = 0);
                  }
                },
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: InteractiveViewer(
              transformationController: _ctrl,
              minScale: 1,
              maxScale: 5,
              onInteractionEnd: (_) => setState(() {}),
              child: SizedBox.expand(child: NetPicture(widget.url, fit: BoxFit.contain, alwaysLoad: true)),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: IconButton(
              tooltip: 'Close',
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ]),
    );
  }
}
